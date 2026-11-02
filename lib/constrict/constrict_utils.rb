# frozen_string_literal: true

require "open3"
require "tempfile"

require_relative "enums"
require_relative "i18n"

module Constrict
  # Raised when ffprobe cannot read a property of a source video.
  #
  # Upstream lets subprocess.CalledProcessError escape the probe helpers and
  # catches it in the two callers that care (`compress`, and the source row's
  # preview); this is the same signal under a name of its own.
  class ProbeError < StandardError; end

  # Ported from upstream's src/constrict_utils.py.
  #
  # The compression backend: it drives ffprobe to read a source video's
  # properties, works out the bitrate and resolution that will land the output
  # under the target size, and runs two-pass ffmpeg transcodes until it does,
  # reporting progress and failed attempts through callbacks. No GTK here —
  # the widgets supply the callbacks.
  module Utils
    MAX_VIDEO_BITRATE = 100_000_000
    MAX_FRAMERATE = 240

    # Bitrate-resolution recommendations, taken upstream from
    # https://developers.google.com/media/vp9/settings/vod — each key is the
    # lowest bitrate in kbps at which the paired resolution is worth using.
    BITRATE_RES_MAP_30 = {
      12_000 => [3840, 2160],
      6_000  => [2560, 1440],
      1_800  => [1920, 1080],
      1_024  => [1280, 720],
      512    => [640, 480],
      276    => [640, 360],
      150    => [320, 240],
      0      => [192, 144],
    }.freeze

    BITRATE_RES_MAP_60 = {
      18_000 => [3840, 2160],
      9_000  => [2560, 1440],
      3_000  => [1920, 1080],
      1_800  => [1280, 720],
      750    => [640, 480],
      276    => [640, 360],
      150    => [320, 240],
      0      => [192, 144],
    }.freeze

    VIDEO_ENCODERS = {
      VideoCodec::H264 => ["libx264", "h264_vaapi"],
      VideoCodec::HEVC => ["libx265", "hevc_vaapi"],
      VideoCodec::AV1  => ["libsvtav1", "av1_vaapi"],
      VideoCodec::VP9  => ["libvpx-vp9", "vp9_vaapi"],
    }.freeze

    # The VA-API profile that has to appear in `vainfo` output for hardware
    # encoding of each codec to be possible.
    VAAPI_PROFILES = {
      VideoCodec::H264 => "VAProfileH264Main",
      VideoCodec::HEVC => "VAProfileHEVCMain",
      VideoCodec::AV1  => "VAProfileAV1Profile0",
      VideoCodec::VP9  => "VAProfileVP9Profile0",
    }.freeze

    COMPATIBLE_SUBTITLE_CODECS = ["subrip", "webvtt", "ass", "mov_text"].freeze

    extend I18n

    module_function

    # --- ffprobe ------------------------------------------------------------

    # The duration of the video in seconds.
    def duration(file_input)
      probe(
        [
          "-v", "error",
          "-show_entries", "format=duration",
          "-of", "default=noprint_wrappers=1:nokey=1",
          file_input,
        ],
      ).to_f
    end

    # The framerate of the video, or -1 when it reports none.
    def framerate(file_input)
      probe(
        [
          "-v", "0",
          "-of", "default=noprint_wrappers=1:nokey=1",
          "-select_streams", "v:0",
          "-show_entries", "stream=avg_frame_rate",
          file_input,
        ],
      ).split("/").then do |numerator, denominator|
        if denominator.to_i.zero?
          -1
        else
          numerator.to_i / denominator.to_f
        end
      end
    end

    # The [width, height] of the video.
    def resolution(file_input)
      probe(
        [
          "-v", "error",
          "-select_streams", "v:0",
          "-show_entries", "stream=width,height",
          "-of", "csv=s=x:p=0",
          file_input,
        ],
      ).split("x").then { |width, height| [width.to_i, height.to_i] }
    end

    # The rotation recorded in the video's side data, or 0 when there is none.
    def rotation(file_input)
      probe(
        [
          "-v", "error",
          "-select_streams", "v:0",
          "-show_entries", "stream_side_data=rotation",
          "-of", "default=noprint_wrappers=1:nokey=1",
          file_input,
        ],
      ).then { |value| Integer(value.strip, exception: false) || 0 }
    end

    # The number of packets in the video stream, which stands in for its frame
    # count. Falls back to 1 so progress arithmetic never divides by zero.
    def frame_count(file_input)
      probe(
        [
          "-v", "error",
          "-select_streams", "v:0",
          "-count_packets",
          "-show_entries", "stream=nb_read_packets",
          "-of", "default=noprint_wrappers=1:nokey=1",
          file_input,
        ],
      ).then { |value| Integer(value.strip, exception: false) || 1 }
    end

    # The bitrate of the first audio stream: 0 when there is no audio at all,
    # and a deliberately high 128 kbps when ffprobe will not say (variable
    # bitrate), so the audio allowance is never underestimated.
    def audio_bitrate(file_input)
      probe(
        [
          "-loglevel", "error",
          "-select_streams", "a:0",
          "-show_entries", "stream=bit_rate",
          "-of", "csv=p=0",
          file_input,
        ],
      ).strip.then do |value|
        if value.empty?
          0
        else
          Integer(value, exception: false) || 128_000
        end
      end
    end

    # The channel count of the first audio stream, defaulting to mono.
    def audio_channel_count(file_input)
      probe(
        [
          "-loglevel", "error",
          "-select_streams", "a:0",
          "-show_entries", "stream=channels",
          "-of", "csv=p=0",
          file_input,
        ],
      ).then { |value| Integer(value.strip, exception: false) || 1 }
    end

    # The indices of the subtitle streams ffmpeg can copy into an MP4.
    def subtitle_streams(file_input)
      probe(
        [
          "-loglevel", "error",
          "-select_streams", "s",
          "-show_entries", "stream=index,codec_name",
          "-of", "csv=p=0",
          file_input,
        ],
      ).strip.split("\n").filter_map do |stream|
        stream.split(",").then do |index, codec|
          if COMPATIBLE_SUBTITLE_CODECS.include?(codec)
            index.to_i
          end
        end
      end
    end

    # --- Encode planning ----------------------------------------------------

    # A resolution preset (the height, or the width of a portrait video) that
    # suits the given bitrate, never larger than the source resolution.
    def res_preset(bitrate, source_width, source_height, framerate)
      width = source_width + (source_width % 2)
      height = source_height + (source_height % 2)
      source_pixels = width * height
      bitrate_kbps = bitrate / 1000.0

      map = BITRATE_RES_MAP_30
      if framerate > 30
        map = BITRATE_RES_MAP_60
      end

      catch(:preset) do
        map.each do |bitrate_lower_bound, (preset_width, preset_height)|
          if bitrate_kbps >= bitrate_lower_bound
            if source_pixels >= preset_width * preset_height
              throw :preset, preset_height
            else
              break
            end
          end
        end

        if height > width
          width
        else
          height
        end
      end
    end

    # The ffmpeg preset (`-preset`, or `-cpu-used` for VP9) to encode with.
    def encoding_speed(frame_height, low_bitrate, codec, extra_quality)
      hd = frame_height > 480

      case codec
      when VideoCodec::H264 then h264_speed(hd, low_bitrate, extra_quality)
      when VideoCodec::HEVC then hevc_speed(hd, extra_quality)
      when VideoCodec::AV1 then av1_speed(hd, low_bitrate, extra_quality)
      when VideoCodec::VP9 then vp9_speed(hd, extra_quality)
      else raise ArgumentError, "unknown codec passed to encoding_speed"
      end
    end

    def h264_speed(hd, low_bitrate, extra_quality)
      if extra_quality && low_bitrate
        "placebo"
      elsif extra_quality || low_bitrate
        "veryslow"
      elsif hd
        "medium"
      else
        "slower"
      end
    end

    def hevc_speed(hd, extra_quality)
      if extra_quality
        "veryslow"
      elsif hd
        "medium"
      else
        "slow"
      end
    end

    def av1_speed(hd, low_bitrate, extra_quality)
      if extra_quality || low_bitrate
        "4"
      elsif hd
        "10"
      else
        "8"
      end
    end

    def vp9_speed(hd, extra_quality)
      if extra_quality
        "0"
      elsif hd
        "5"
      else
        "4"
      end
    end

    def video_encoder(codec, use_ha)
      VIDEO_ENCODERS.fetch(codec).then do |software, hardware|
        if use_ha
          hardware
        else
          software
        end
      end
    end

    # Whether the GPU can encode the given codec, read out of `vainfo`.
    def ha_work?(codec)
      vainfo_entries.then do |entries|
        VAAPI_PROFILES.fetch(codec).then do |profile|
          entries.include?("#{profile}:VAEntrypointEncSlice") ||
            entries.include?("#{profile}:VAEntrypointEncSliceLP")
        end
      end
    end

    # Returns [video bitrate, audio bitrate, preset height, framerate] for the
    # target size and the user's preferences.
    #
    # `factor` is the correction a previous attempt's overshoot or undershoot
    # feeds back in; `force_crush` and `locked_in_height` likewise carry
    # decisions made by earlier attempts.
    def encode_settings(
      target_size_mib:,
      fps_mode:,
      width:,
      height:,
      fps:,
      duration:,
      audio_bitrate:,
      factor: 1.0,
      force_crush: false,
      locked_in_height: nil,
      basic_transcode: false
    )
      target_bitrate = (target_size_mib * 1024 * 1024 * 8 / duration).round * factor
      # To account for metadata and such, to prevent overshooting.
      target_bitrate = (target_bitrate * 0.965).round

      # Crush mode trades audio quality and framerate for image clarity. The
      # 246 kbps threshold is 240p's lowest recommended video bitrate (150)
      # plus a good Opus audio bitrate (96): below it, dropping audio to
      # 12 kbps can keep the video out of the 144p bracket entirely.
      crush_mode = (target_bitrate / 1000.0) < (150 + 96) || force_crush

      max_audio_bitrate = max_audio_bitrate(target_bitrate, crush_mode)
      target_audio_bitrate = [audio_bitrate, max_audio_bitrate].min
      target_video_bitrate = [
        target_bitrate - target_audio_bitrate,
        MAX_VIDEO_BITRATE,
      ].min

      if basic_transcode
        [
          target_video_bitrate,
          target_audio_bitrate,
          [width, height].min,
          [fps, MAX_FRAMERATE].min,
        ]
      else
        auto_encode_settings(
          target_video_bitrate: target_video_bitrate,
          target_audio_bitrate: target_audio_bitrate,
          fps_mode:             fps_mode,
          width:                width,
          height:               height,
          fps:                  fps,
          crush_mode:           crush_mode,
          locked_in_height:     locked_in_height,
        )
      end
    end

    def max_audio_bitrate(target_bitrate, crush_mode)
      if crush_mode
        [(target_bitrate * 0.2).to_i, 12_000].max
      elsif target_bitrate <= 96_000 * 20
        96_000
      else
        [(target_bitrate * 0.05).to_i, 128_000].min
      end
    end

    # --- Transcoding --------------------------------------------------------

    # Runs the two ffmpeg passes for one compression attempt.
    #
    # Returns nil when the transcode finished or was cancelled, and the text of
    # ffmpeg's stderr when it failed.
    def transcode(
      file_input:,
      file_output:,
      video_bitrate:,
      audio_bitrate:,
      width:,
      height:,
      rotation:,
      subtitle_streams:,
      framerate:,
      codec:,
      use_ha:,
      extra_quality:,
      frame_count:,
      log_path:,
      cancel_event:,
      &output_fn
    )
      frame_height = [width, height].min
      low_bitrate = video_bitrate < 276_000
      # Hardware encoders cannot hold a sensible picture this low, so the
      # software encoder takes over whatever the user asked for.
      hardware = use_ha && !low_bitrate
      preset = encoding_speed(
        frame_height,
        low_bitrate,
        codec,
        extra_quality,
      )

      options = {
        codec:         codec,
        file_input:    file_input,
        framerate:     framerate,
        hardware:      hardware,
        height:        height,
        log_path:      log_path,
        preset:        preset,
        video_bitrate: video_bitrate,
        width:         width,
        rotation:      rotation,
      }

      catch(:transcode) do
        if cancel_event.call
          throw :transcode, nil
        end

        # VP9's first software pass reports no progress at all, so it is run
        # without a pass number and the progress bar pulses through it; every
        # other combination reports both passes as one 0-100% run.
        vp9_software = codec == VideoCodec::VP9 && !hardware
        pass_number = 0
        if vp9_software
          pass_number = nil
        end

        avg_fps, error = progress(
          ffmpeg_cmd:        pass1_cmd(**options),
          frame_count:       frame_count,
          pass_num:          pass_number,
          last_pass_avg_fps: nil,
          cancel_event:      cancel_event,
          &output_fn
        )

        if error
          throw :transcode, error
        end

        if cancel_event.call
          throw :transcode, nil
        end

        second_pass_number = 1
        if vp9_software
          second_pass_number = nil
        end

        _, pass2_error = progress(
          ffmpeg_cmd:        pass2_cmd(
            **options,
            audio_bitrate:    audio_bitrate,
            audio_channels:   [audio_channel_count(file_input), 2].min,
            file_output:      file_output,
            subtitle_streams: subtitle_streams,
          ),
          frame_count:       frame_count,
          pass_num:          second_pass_number,
          last_pass_avg_fps: avg_fps,
          cancel_event:      cancel_event,
          &output_fn
        )

        pass2_error
      end
    end

    # Streams an ffmpeg command's `-progress` output to the block, as a
    # fraction of the whole job and an estimate of the seconds remaining.
    #
    # Returns [average fps, error text]. The average fps is handed to the
    # second pass so its time estimate does not start from nothing.
    def progress(
      ffmpeg_cmd:,
      frame_count:,
      pass_num:,
      last_pass_avg_fps:,
      cancel_event:
    )
      Tempfile.create("constrict-ffmpeg-err") do |err_file|
        state = {
          avg_counter:   0,
          cancelled:     false,
          fps:           last_pass_avg_fps,
          fps_sum:       0.0,
          frame:         0,
          pulse_counter: 0,
        }
        status = nil

        IO.popen(ffmpeg_cmd, "r", err: err_file.path) do |stdout|
          stdout.each_line do |line|
            read_progress_line(
              line:              line,
              state:             state,
              frame_count:       frame_count,
              pass_num:          pass_num,
              last_pass_avg_fps: last_pass_avg_fps,
            ) { |fraction, seconds_left| yield(fraction, seconds_left) }

            if cancel_event.call
              state[:cancelled] = true
              Process.kill("KILL", stdout.pid)
              break
            end
          end
          status = Process.wait2(stdout.pid)[1]
        rescue Errno::ECHILD, Errno::ESRCH
          status = nil
        end

        avg = nil
        if state[:avg_counter].positive?
          avg = state[:fps_sum] / state[:avg_counter]
        end

        if state[:cancelled]
          [nil, nil]
        elsif status.nil? || status.success?
          [avg, nil]
        else
          [avg, File.read(err_file.path)]
        end
      end
    end

    # One line of ffmpeg's `-progress` stream. `frame=` lines record where the
    # encode is; `fps=` lines are what the progress report is pegged to, since
    # they arrive at a steady, readable rate.
    def read_progress_line(
      line:,
      state:,
      frame_count:,
      pass_num:,
      last_pass_avg_fps:
    )
      if line.start_with?("frame=")
        state[:frame] = line[/[0-9]+/].to_i
      elsif line.start_with?("fps=")
        state[:pulse_counter] += 1
        read_fps(
          line:              line,
          state:             state,
          pass_num:          pass_num,
          last_pass_avg_fps: last_pass_avg_fps,
        )

        passes = 2
        if pass_num.nil?
          passes = 1
        end

        total_frames = frame_count * passes
        current_frame = (frame_count * (pass_num || 0)) + state[:frame]
        seconds_left = seconds_left(total_frames - current_frame, state[:fps])

        # ffmpeg can report more frames than ffprobe counted packets, which
        # would push the fraction past 1.0; the end of a pass is pinned to its
        # share of the job instead, and the last pass says "almost done".
        if state[:frame] > frame_count
          if pass_num == 0
            yield(0.5, seconds_left)
          else
            yield(1.0, -1)
          end
        else
          yield(current_frame.to_f / total_frames, seconds_left)
        end
      end
    end

    # The first frames of a pass have anomalously low fps while the encoder
    # warms up. Pass 1 gets ten readings of grace and shows no estimate until
    # then; pass 2 gets twenty and borrows pass 1's average, because a jumpy
    # estimate appearing at the 50% mark reads worse than none at all.
    def read_fps(line:, state:, pass_num:, last_pass_avg_fps:)
      warming_up = state[:pulse_counter] < 10 ||
        (pass_num == 1 && state[:pulse_counter] < 20)

      if warming_up
        state[:fps] = last_pass_avg_fps
      else
        line[/[0-9]+[.]?[0-9]*/].then do |reading|
          if reading
            state[:fps] = reading.to_f
            state[:avg_counter] += 1
            state[:fps_sum] += state[:fps]
          end
        end
      end
    end

    def seconds_left(frames_left, fps)
      if fps && fps.positive?
        [(frames_left / fps).to_i, 0].max
      end
    end

    # --- Compression --------------------------------------------------------

    # Iteratively transcodes the input until the output reasonably meets the
    # target size.
    #
    # Returns the output's size in bytes on success, a string of error details
    # on failure, and nil when it stopped for any other reason (cancellation).
    def compress(
      file_input:,
      input_mime_type:,
      file_output:,
      target_size_mib:,
      framerate_option:,
      extra_quality:,
      codec:,
      use_ha:,
      tolerance:,
      log_path:,
      cancel_event:,
      on_new_attempt:,
      on_attempt_fail:,
      &output_fn
    )
      output_fn.call(0, nil)

      catch(:result) do
        unless File.file?(file_input)
          throw :result,
            _(
              "Constrict: Could not read input file. Was it moved or deleted " \
              "before compression?",
            )
        end

        target_bytes_limit = target_size_mib * 1024 * 1024
        before_size_bytes = File.size(file_input)
        # A video already under the target is transcoded once at its own size
        # rather than compressed towards a smaller one.
        do_basic_transcode = before_size_bytes <= target_bytes_limit

        source = probed_source(file_input)

        creation_error = create_output_file(file_output)
        if creation_error
          throw :result, creation_error
        end

        target_bytes = target_bytes_limit
        if do_basic_transcode
          target_bytes = before_size_bytes
        end

        run_attempts(
          cancel_event:       cancel_event,
          codec:              codec,
          do_basic_transcode: do_basic_transcode,
          extra_quality:      extra_quality,
          file_input:         file_input,
          file_output:        file_output,
          framerate_option:   framerate_option,
          input_mime_type:    input_mime_type,
          log_path:           log_path,
          on_attempt_fail:    on_attempt_fail,
          on_new_attempt:     on_new_attempt,
          before_size_bytes:  before_size_bytes,
          source:             source,
          target_bytes:       target_bytes,
          target_bytes_limit: target_bytes_limit,
          tolerance:          tolerance,
          use_ha:             use_ha && !extra_quality && ha_work?(codec),
          &output_fn
        )
      end
    end

    # --- Internals ----------------------------------------------------------

    # Runs ffprobe and returns its stdout. A non-zero exit means the property
    # could not be read, which is what marks a source video as broken.
    def probe(arguments)
      Open3.capture2("ffprobe", *arguments).then do |stdout, status|
        unless status.success?
          raise ProbeError, "ffprobe failed: #{arguments.join(" ")}"
        end

        stdout
      end
    rescue Errno::ENOENT
      raise ProbeError, "ffprobe is not installed"
    end

    # Reading the source's properties is where a missing or corrupted file is
    # discovered, and that ends the whole compression.
    def probed_source(file_input)
      probe_source(file_input)
    rescue ProbeError
      throw :result,
        _(
          "Constrict: Could not retrieve video properties. " \
          "Source video may be missing or corrupted.",
        )
    end

    # Every property `compress` needs from the source, read in one go so a
    # failure to read any of them is one failure.
    def probe_source(file_input)
      framerate(file_input).then do |source_fps|
        if source_fps == -1
          source_fps = 60
        end

        resolution(file_input).then do |width, height|
          {
            audio_bitrate:    audio_bitrate(file_input),
            duration:         duration(file_input),
            frame_count:      frame_count(file_input),
            fps:              source_fps,
            height:           height,
            rotation:         rotation(file_input),
            subtitle_streams: subtitle_streams(file_input),
            width:            width,
          }
        end
      end
    end

    # Reserves the export path before encoding, so two concurrent runs cannot
    # pick the same name. Returns nil on success, or the error to report.
    def create_output_file(file_output)
      File.open(file_output, File::WRONLY | File::CREAT | File::EXCL).close
      nil
    rescue Errno::EEXIST
      _(
        "Constrict: Could not create exported file. A file with the " \
        "reserved name already exists.",
      )
    rescue Errno::EACCES, Errno::EPERM, Errno::EROFS
      _(
        "Constrict: Could not create exported file. There are " \
        "insufficient permissions to create a file at the requested export " \
        "path.",
      )
    end

    def vainfo_entries
      Open3.capture2("vainfo", "--display", "drm").then do |stdout, status|
        if status.success?
          stdout.delete(" \t").split("\n")
        else
          []
        end
      end
    end

    # The framerate cap and resolution preset for a target bitrate.
    def auto_encode_settings(
      target_video_bitrate:,
      target_audio_bitrate:,
      fps_mode:,
      width:,
      height:,
      fps:,
      crush_mode:,
      locked_in_height:
    )
      preset_height = nil
      max_fps = 60.0

      if crush_mode
        max_fps = 24.0
      elsif fps_mode == FpsMode::PREFER_CLEAR
        max_fps = 30.0
      elsif fps_mode == FpsMode::PREFER_SMOOTH
        max_fps = 60.0
      elsif fps_mode == FpsMode::AUTO
        # 60 FPS is only worth it where it costs no resolution, and only from
        # 720p up — below that the lost clarity is the more visible trade.
        preset_height = res_preset(
          target_video_bitrate,
          width,
          height,
          30.0,
        )
        heights_match = preset_height == res_preset(
          target_video_bitrate,
          width,
          height,
          60.0,
        )
        if heights_match && preset_height >= 720
          max_fps = 60.0
        else
          max_fps = 30.0
        end
      end

      target_fps = [fps, max_fps].min

      if preset_height.nil?
        preset_height = res_preset(
          target_video_bitrate,
          width,
          height,
          target_fps,
        )
      end

      if locked_in_height && preset_height >= locked_in_height
        preset_height = locked_in_height
      end

      [target_video_bitrate, target_audio_bitrate, preset_height, target_fps]
    end

    # The shared head of both ffmpeg passes: input, scaling and the encoder.
    def common_cmd(
      codec:,
      file_input:,
      framerate:,
      hardware:,
      height:,
      log_path:,
      preset:,
      rotation:,
      width:,
      pass_preset:
    )
      preset_name = "-preset"
      if codec == VideoCodec::VP9
        preset_name = "-cpu-used"
      end

      gpu_filters = ""
      if hardware
        gpu_filters = ",format=nv12,hwupload"
      end

      cmd = ["ffmpeg", "-y", "-progress", "-"]

      if hardware
        cmd.push("-vaapi_device", "/dev/dri/renderD128")
      end

      cmd.push(

        "-display_rotation",

        rotation.to_s,
        "-noautorotate",
        "-i",

        file_input,
        preset_name,

        pass_preset,
        "-vf",

        "scale=#{width}:#{height}#{gpu_filters}",

      )

      if log_path
        cmd.push("-passlogfile", log_path)
      end

      if codec == VideoCodec::VP9
        cmd.push(
          "-deadline",
          "good",
          "-row-mt",
          "1",
          "-frame-parallel",
          "1",
        )
      end

      if codec == VideoCodec::H264
        cmd.push("-profile:v", "main")
      end

      if framerate != -1
        cmd.push("-r", framerate.to_s)
      end

      cmd
    end

    # Pass 1 analyses the video and writes the log pass 2 reads; it encodes to
    # /dev/null with no audio and no subtitles.
    def pass1_cmd(**options)
      pass_preset = options.fetch(:preset)
      if options.fetch(:codec) == VideoCodec::VP9
        pass_preset = "4"
      end

      common_cmd(**options, pass_preset: pass_preset).push(

        "-c:v",

        video_encoder(options.fetch(:codec), options.fetch(:hardware)),
        "-b:v",

        options.fetch(:video_bitrate).to_s,
        "-pix_fmt",

        "yuv420p",
        "-pass",

        "1",
        "-an",
        "-sn",
        "-f",

        "null",
        "/dev/null",

      )
    end

    # Pass 2 writes the real MP4: video at the planned bitrate, Opus audio
    # downmixed to at most stereo, and any subtitle streams MP4 can carry.
    def pass2_cmd(
      audio_bitrate:,
      audio_channels:,
      file_output:,
      subtitle_streams:,
      **options
    )
      common_cmd(**options, pass_preset: options.fetch(:preset)).tap do |cmd|
        cmd.push(

          "-c:v",

          video_encoder(options.fetch(:codec), options.fetch(:hardware)),
          "-b:v",

          options.fetch(:video_bitrate).to_s,
          "-pix_fmt",

          "yuv420p",
          "-pass",

          "2",
          "-c:a",

          "libopus",
          "-b:a",

          audio_bitrate.to_s,
          "-ac",

          audio_channels.to_s,
          "-map",

          "0:v:0",
          "-map",

          "0:a:0?",
          "-map_chapters",

          "-1",

        )

        subtitle_streams.each { |index| cmd.push("-map", "0:#{index}") }

        cmd.push(
          "-c:s",
          "mov_text",
          "-f",
          "mp4",
          file_output,
        )
      end
    end

    # The attempt loop. Each attempt transcodes once, measures the result, and
    # feeds the overshoot back as a bitrate correction factor until the output
    # lands inside the tolerance band below the target.
    def run_attempts(
      before_size_bytes:,
      cancel_event:,
      codec:,
      do_basic_transcode:,
      extra_quality:,
      file_input:,
      file_output:,
      framerate_option:,
      input_mime_type:,
      log_path:,
      on_attempt_fail:,
      on_new_attempt:,
      source:,
      target_bytes:,
      target_bytes_limit:,
      tolerance:,
      use_ha:,
      &output_fn
    )
      state = {
        after_size_bytes:  0,
        attempt:           0,
        displayed_res:     0,
        factor:            1.0,
        force_crush:       false,
        is_hq_audio:       nil,
        lowest_res:        nil,
        percent_of_target: 200.0,
        target_fps:        0.0,
        video_bitrate:     0,
      }

      catch(:attempts) do
        while state[:percent_of_target] < (100 - tolerance) ||
            state[:percent_of_target] > 100
          if state[:attempt].positive?
            on_attempt_fail.call(
              state[:attempt],
              state[:video_bitrate],
              state[:is_hq_audio],
              state[:displayed_res],
              state[:target_fps],
              state[:after_size_bytes],
              target_bytes_limit,
            )
          end

          state[:attempt] += 1

          settings = encode_settings(
            target_size_mib:  target_bytes / 1024.0 / 1024.0,
            fps_mode:         framerate_option,
            width:            source.fetch(:width),
            height:           source.fetch(:height),
            fps:              source.fetch(:fps),
            duration:         source.fetch(:duration),
            audio_bitrate:    source.fetch(:audio_bitrate),
            factor:           state[:factor],
            force_crush:      state[:force_crush],
            locked_in_height: state[:lowest_res],
            basic_transcode:  do_basic_transcode,
          )

          video_bitrate, audio_bitrate, preset_height, target_fps = settings
          state[:video_bitrate] = video_bitrate
          state[:target_fps] = target_fps
          state[:displayed_res] = preset_height
          state[:is_hq_audio] = hq_audio(audio_bitrate)

          # Once audio has been crushed it stays crushed, so later attempts do
          # not flip between high- and low-quality audio.
          if state[:is_hq_audio] == false
            state[:force_crush] = true
          end

          on_new_attempt.call(
            state[:attempt],
            video_bitrate,
            state[:is_hq_audio],
            preset_height,
            target_fps,
          )
          output_fn.call(0, nil)

          # Below 5 kbps barely anything in the video is perceptible.
          if video_bitrate < 5000
            throw :attempts,
              _(
                "Constrict: Video bitrate got too low (<5 " \
                "kbps). The target size may be too low for this file.",
              )
          end

          width, height = scaled_resolution(
            preset_height,
            source.fetch(:width),
            source.fetch(:height),
          )

          transcode_error = transcode(
            file_input:       file_input,
            file_output:      file_output,
            video_bitrate:    video_bitrate,
            audio_bitrate:    audio_bitrate,
            width:            width,
            height:           height,
            rotation:         source.fetch(:rotation),
            subtitle_streams: source.fetch(:subtitle_streams),
            framerate:        target_fps,
            codec:            codec,
            use_ha:           use_ha,
            extra_quality:    extra_quality,
            frame_count:      dest_frame_count(
              input_mime_type: input_mime_type,
              source:          source,
              target_fps:      target_fps,
            ),
            log_path:         log_path,
            cancel_event:     cancel_event,
            &output_fn
          )

          if transcode_error
            throw :attempts, transcode_error
          end

          if cancel_event.call
            throw :attempts, nil
          end

          unless File.exist?(file_output)
            throw :attempts,
              _(
                "Constrict: Cannot read output file. Was " \
                "it moved or deleted mid-compression?",
              )
          end

          state[:after_size_bytes] = File.size(file_output)
          state[:percent_of_target] =
            (100.0 / target_bytes_limit) * state[:after_size_bytes]

          if video_bitrate >= MAX_VIDEO_BITRATE
            # No point repeating when the bitrate is already at its ceiling.
            break
          end

          if state[:percent_of_target] < 100 &&
              (do_basic_transcode || state[:attempt] > 1)
            if do_basic_transcode
              percent_of_original =
                (100.0 / before_size_bytes) * state[:after_size_bytes]
              if percent_of_original >= (100 - tolerance) || state[:attempt] > 1
                break
              end

              # Worth one more attempt at a higher bitrate, measured against
              # the original size rather than the target.
              state[:percent_of_target] = percent_of_original
            else
              # The quality will not get better than this; another attempt
              # would be pointless.
              break
            end
          end

          if state[:percent_of_target] > 50
            # Do not transcode to a higher resolution in later attempts.
            state[:lowest_res] = [width, height].min
          end

          # The 0.98 keeps attempts from clustering just above the target.
          state[:factor] *= 0.98 * (100 / state[:percent_of_target])
        end

        state[:after_size_bytes]
      end
    end

    # nil when the video has no audio at all, otherwise whether its audio
    # survived at a quality worth calling high.
    def hq_audio(audio_bitrate)
      if audio_bitrate.positive?
        audio_bitrate > 12_000
      end
    end

    # Scales the source resolution to the preset, keeping the aspect ratio and
    # rounding both dimensions to the even numbers ffmpeg's encoders want.
    def scaled_resolution(preset_height, source_width, source_height)
      if source_height > source_width
        target_width = preset_height
        scaling_factor = source_width / target_width.to_f
        [target_width, (((source_height / scaling_factor) + 1).to_i / 2) * 2]
      else
        scaling_factor = source_height / preset_height.to_f
        [(((source_width / scaling_factor) + 1).to_i / 2) * 2, preset_height]
      end
    end

    # How many frames the output will have, which is what progress is measured
    # against. An animated GIF keeps every frame; anything else loses frames in
    # proportion to the framerate cap.
    def dest_frame_count(input_mime_type:, source:, target_fps:)
      if input_mime_type == "image/gif"
        source.fetch(:frame_count)
      else
        (source.fetch(:frame_count) / (source.fetch(:fps) / target_fps)).to_i
      end.then { |count| [count, 1].max }
    end
  end
end
