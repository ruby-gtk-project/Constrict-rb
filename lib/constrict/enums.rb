# frozen_string_literal: true

module Constrict
  # Ported from upstream's src/enums.py.
  #
  # Upstream declares three classes of bare integer constants. The values are
  # part of the file format — the GSettings schema stores `fps-mode` and
  # `video-codec` by these numbers, and the codec number indexes the codec
  # dropdown's string list — so they are reproduced exactly.
  module FpsMode
    AUTO = 0
    PREFER_CLEAR = 1
    PREFER_SMOOTH = 2

    # The nicknames the GSettings schema's FpsMode enum uses, by value.
    NICKS = {
      AUTO          => "auto",
      PREFER_CLEAR  => "prefer-clear",
      PREFER_SMOOTH => "prefer-smooth",
    }.freeze

    def self.from_nick(nick) = NICKS.key(nick.to_s) || AUTO
    def self.nick(value) = NICKS.fetch(value, "auto")
  end

  # Ported from upstream's src/enums.py.
  module VideoCodec
    H264 = 0
    HEVC = 1
    AV1 = 2
    VP9 = 3

    # The nicknames the GSettings schema's VideoCodec enum uses, by value.
    NICKS = {
      H264 => "h264",
      HEVC => "hevc",
      AV1  => "av1",
      VP9  => "vp9",
    }.freeze

    def self.from_nick(nick) = NICKS.key(nick.to_s) || H264
    def self.nick(value) = NICKS.fetch(value, "h264")
  end

  # Ported from upstream's src/enums.py.
  #
  # The seven states a source row moves between. PENDING is the state a freshly
  # staged row starts in; WARN is the only non-PENDING state that still allows
  # an export.
  module SourceState
    PENDING = 0
    COMPRESSING = 1
    COMPLETE = 2
    ERROR = 3
    BROKEN = 4
    INCOMPATIBLE = 5
    WARN = 6
  end
end
