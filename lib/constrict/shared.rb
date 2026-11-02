# frozen_string_literal: true

require "fileutils"
require "adwaita"

require_relative "i18n"

module Constrict
  # Ported from upstream's src/shared.py.
  #
  # Two helpers every other file leans on: the temp directory ffmpeg log files
  # and thumbnails are written to, and the shim that decides whether a UI
  # update runs inline or has to be bounced through the main loop.
  module Shared
    extend I18n

    module_function

    # Returns the path of the app's directory inside the system temp directory,
    # creating it if needed, or nil when it cannot be created.
    #
    # Upstream calls GLib.mkdir_with_parents, which the Ruby bindings do not
    # expose; FileUtils.mkdir_p with the same 0755 mode is the equivalent.
    def tmp_dir
      File.join(GLib.tmp_dir, "constrict").then do |path|
        begin
          FileUtils.mkdir_p(path, mode: 0o755)
          path
        rescue SystemCallError
          warn "Warning: could not get tmp directory"
          nil
        end
      end
    end

    # Runs a block either directly or through GLib::Idle.add.
    #
    # Compression runs on a Ruby thread, and GTK may only be touched from the
    # main loop, so every UI call made from that thread goes through
    # GLib::Idle.add. Calling idle_add from the main thread instead causes its
    # own glitches upstream, hence the flag rather than always deferring.
    def update_ui(daemon)
      if daemon
        GLib::Idle.add do
          yield
          GLib::Source::REMOVE
        end
      else
        yield
      end
    end

    # The resolution/framerate and audio-quality summary both the running
    # attempt and the failed-attempt boxes print after a bitrate, e.g.
    # "1080p@30, HQ audio". `is_hq_audio` is nil for a video with no audio.
    def res_fps_details(is_hq_audio:, vid_height:, vid_fps:)
      "#{vid_height}p@#{vid_fps.round}".then do |res_fps|
        if is_hq_audio.nil?
          res_fps
        else
          interpolate(
            _("{res_fps}, {audio_quality} audio"),
            res_fps:       res_fps,
            audio_quality: is_hq_audio ? _("HQ") : _("LQ"),
          )
        end
      end
    end

    # Upstream reaches for GLib.markup_escape_text, which the Ruby bindings do
    # not wrap. Pango markup needs the same five entities XML does.
    def markup_escape(text)
      text.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub('"', "&quot;")
        .gsub("'", "&apos;")
    end
  end
end
