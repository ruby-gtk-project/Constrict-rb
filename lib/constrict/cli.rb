# frozen_string_literal: true

require "io/console"
require "optparse"
require "tempfile"

require_relative "constrict_utils"
require_relative "enums"

module Constrict
  # Ported from upstream's src/constrict_cli.py.
  #
  # `constrict-cli` compresses one video without a window: the same backend,
  # driven by command-line options, printing attempts and a percentage with an
  # ETA to the terminal. There is no GTK here — this runs where the app cannot.
  class Cli
    FPS_MODES = {
      "auto"          => FpsMode::AUTO,
      "prefer-clear"  => FpsMode::PREFER_CLEAR,
      "prefer-smooth" => FpsMode::PREFER_SMOOTH,
    }.freeze

    CODECS = {
      "h264" => VideoCodec::H264,
      "hevc" => VideoCodec::HEVC,
      "av1"  => VideoCodec::AV1,
      "vp9"  => VideoCodec::VP9,
    }.freeze

    FRAMERATE_HELP = <<~HELP
      The maximum framerate to apply to the output file. NOTE: this option has
      no bearing on source videos at 30 FPS or below, and the output will be
      the same regardless of the option set. Additionally, videos compressed to
      very low bitrates will have their framerate capped to 24 FPS regardless
      of the option set.

      auto: auto-apply a 60 FPS maximum framerate in cases where the percieved
      reduction in image clarity from 30 FPS is negligable.

      prefer-clear: apply a 30 FPS framerate cap, ensuring higher image clarity
      in fewer frames.

      prefer-smooth: apply a 60 FPS framerate cap, ensuring smoothness at a
      cost to image clarity and sometimes resolution
    HELP

    CODEC_HELP = <<~HELP
      The codec used to encode the compressed video.
      h264: uses the H.264 codec. Compatible with most devices and services,
      but with relatively low compression efficiency.
      hevc: uses the H.265 (HEVC) codec. Less compatible with devices and
      services, and is slower to encode, but has higher compression efficiency.
      av1: uses the AV1 codec. High compression efficiency, and is open source
      and royalty free. However, it is less widely supported, and may not embed
      properly on some services.
      vp9: uses the VP9 codec.
    HELP

    MIME_TYPES = {
      ".gif"  => "image/gif",
      ".mkv"  => "video/x-matroska",
      ".mov"  => "video/quicktime",
      ".mp4"  => "video/mp4",
      ".webm" => "video/webm",
    }.freeze

    def self.run(argv) = new(argv).run

    def initialize(argv)
      @argv = argv
      @options = {
        codec:            "h264",
        extra_quality:    false,
        framerate_option: "auto",
        software_encode:  false,
        tolerance:        25,
      }
    end

    def run
      parse

      puts "Compressing #{@options.fetch(:file_path)} to #{@options.fetch(:target_size)} MiB..."

      report(compress)
    end

    private

      def parse
        parser.parse(@argv)

        missing = [:file_path, :target_size, :output].reject { |key| @options.key?(key) }

        unless missing.empty?
          warn parser.help
          raise OptionParser::MissingArgument, missing.join(", ")
        end
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.program_name = "constrict-cli"

          opts.on("-i PATH", "Location of the video file to be compressed") do |value|
            @options[:file_path] = value
          end

          opts.on("-s SIZE", Integer, "Desired size of the compressed video in MiB") do |value|
            @options[:target_size] = value
          end

          opts.on("-t PERCENT", Integer, "Tolerance of end file size under target in percent (default 25)") do |value|
            @options[:tolerance] = value
          end

          opts.on("-o PATH", "Destination path of the compressed video file") do |value|
            @options[:output] = value
          end

          opts.on("--framerate MODE", FPS_MODES.keys, FRAMERATE_HELP) do |value|
            @options[:framerate_option] = value
          end

          opts.on("--extra-quality", "Increase image quality at the cost of much longer encoding times") do
            @options[:extra_quality] = true
          end

          opts.on("--codec CODEC", CODECS.keys, CODEC_HELP) do |value|
            @options[:codec] = value
          end

          opts.on("--software-encode", "Do not use GPU encoding when available") do
            @options[:software_encode] = true
          end
        end
      end

      def compress
        Tempfile.create("constrict-cli-2pass") do |log_file|
          Utils.compress(
            file_input:       @options.fetch(:file_path),
            input_mime_type:  mime_type,
            file_output:      @options.fetch(:output),
            target_size_mib:  @options.fetch(:target_size),
            framerate_option: FPS_MODES.fetch(@options.fetch(:framerate_option)),
            extra_quality:    @options.fetch(:extra_quality),
            codec:            CODECS.fetch(@options.fetch(:codec)),
            use_ha:           !@options.fetch(:software_encode),
            tolerance:        @options.fetch(:tolerance),
            log_path:         log_file.path,
            cancel_event:     -> { false },
            on_new_attempt:   method(:show_attempt_details).to_proc,
            on_attempt_fail:  method(:show_attempt_fail).to_proc,
            &method(:print_progress)
          )
        end
      rescue Interrupt
        puts "\n\n*** Compression Cancelled ***"
        nil
      end

      def report(result)
        if result.is_a?(String)
          puts "\n\n*** COMPRESSION ERROR ***"
          puts result
        elsif result.is_a?(Integer)
          puts "\n\nVideo compressed to #{(result / 1024.0 / 1024.0).round(1)} MiB."
        end
      end

      # Ruby has no mimetypes module; the extensions the app accepts are the
      # ones that matter, and only "image/gif" changes how the backend counts
      # frames.
      def mime_type
        MIME_TYPES.fetch(
          File.extname(@options.fetch(:file_path)).downcase,
          "video/mp4",
        )
      end

      # The progress line is rewritten in place, padded to the terminal width
      # so a shorter line never leaves the tail of a longer one behind.
      def print_progress(fraction, seconds_left)
        (fraction * 100).round.then do |percent|
          unless percent.zero?
            print(bold(pad("\r   #{percent}%#{eta(seconds_left)}")))
          end
        end
      end

      def eta(seconds_left)
        if seconds_left
          minutes = seconds_left / 60
          " (ETA #{minutes / 60}:#{minutes % 60}:#{seconds_left % 60})"
        else
          ""
        end
      end

      def show_attempt_details(attempt, bitrate, hq_audio, height, fps)
        details = "#{height}p@#{fps.round}"
        unless hq_audio.nil?
          quality = "LQ"
          if hq_audio
            quality = "HQ"
          end

          details = "#{details}, #{quality} audio"
        end

        puts "\n:: Attempt #{attempt} -- #{bitrate / 1000}kbps (#{details})"
      end

      def show_attempt_fail(_attempt, _bitrate, _hq_audio, _height, _fps, after_bytes, _target_bytes)
        puts "\n   Attempt fail: compressed size is #{(after_bytes / 1024.0 / 1024.0).round(1)}MiB"
      end

      def bold(text) = "\033[1m#{text}\033[0m"

      def pad(text)
        terminal_width.then do |columns|
          "#{text}#{" " * [columns - text.length, 0].max}"
        end
      end

      def terminal_width
        IO.console_size[1]
      rescue StandardError
        80
      end
  end
end
