# frozen_string_literal: true

require "json"
require "fileutils"

require_relative "enums"

module Constrict
  # Settings holds the same keys as upstream's GSettings schema,
  # data/io.github.wartybix.Constrict.gschema.xml.in.
  #
  # Upstream uses GSettings, which needs a compiled schema installed into the
  # system's glib-2.0/schemas directory. Requiring an install step to run the
  # app from a checkout is worse than the alternative, so the same eleven keys,
  # their defaults and their semantics are backed by a small JSON file under
  # XDG_CONFIG_HOME instead.
  #
  # The two enum keys (`fps-mode`, `video-codec`) are stored by nickname, as
  # the schema's `<enum>` elements do, and read back as the integers
  # Constrict::FpsMode and Constrict::VideoCodec define.
  class Settings
    DEFAULTS = {
      "window-width"          => 1000,
      "window-height"         => 700,
      "window-maximized"      => false,
      "target-size"           => 10,
      "fps-mode"              => "auto",
      "video-codec"           => "h264",
      "extra-quality"         => false,
      "tolerance"             => 25,
      "open-initial-folder"   => "",
      "export-initial-folder" => "",
      "use-gpu-encoding"      => true,
      "custom-export-suffix"  => "",
    }.freeze

    def initialize(path: nil)
      @path = path || default_path
      @values = DEFAULTS.merge(read)
    end

    def location = @path

    def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

    def []=(key, value)
      @values[key.to_s] = value
      write
      value
    end

    def default_value(key) = DEFAULTS[key.to_s]

    # The enum keys, read and written as the integers the rest of the app uses.
    def fps_mode = FpsMode.from_nick(self["fps-mode"])
    def video_codec = VideoCodec.from_nick(self["video-codec"])

    def fps_mode=(value)
      self["fps-mode"] = FpsMode.nick(value)
    end

    def video_codec=(value)
      self["video-codec"] = VideoCodec.nick(value)
    end

    # Named accessors for the plain keys, so callers do not repeat the strings.
    (DEFAULTS.keys - ["fps-mode", "video-codec"]).each do |key|
      method_name = key.tr("-", "_")
      define_method(method_name) { self[key] }
      define_method(:"#{method_name}=") { |value| self[key] = value }
      if [true, false].include?(DEFAULTS[key])
        define_method(:"#{method_name}?") { self[key] == true }
      end
    end

    private

      def default_path
        File.join(
          ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config")),
          "constrict-rb",
          "settings.json",
        )
      end

      def read
        if File.exist?(@path)
          JSON.parse(File.read(@path))
        else
          {}
        end
      rescue JSON::ParserError => e
        warn "Error parsing #{@path}: #{e.message}"
        {}
      end

      def write
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.pretty_generate(@values))
      end
  end
end
