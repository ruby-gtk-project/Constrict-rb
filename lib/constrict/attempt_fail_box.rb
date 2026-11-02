# frozen_string_literal: true

require "adwaita"

require_relative "i18n"
require_relative "shared"

module Constrict
  # Ported from upstream's src/attempt_fail_box.blp and
  # src/attempt_fail_box.py.
  #
  # One failed compression attempt, listed in a source row's compression
  # popover below the attempt that is currently running: what the attempt was
  # aiming for, and whether the file it produced came out too large or too
  # small, with an arrow pointing the way it missed.
  class AttemptFailBox < Gtk::Box
    include I18n

    type_register

    def initialize(
      attempt_no:,
      vid_bitrate:,
      is_hq_audio:,
      vid_height:,
      vid_fps:,
      compressed_size_bytes:,
      target_size_bytes:
    )
      super()
      self.orientation = :vertical
      @attempt_no = attempt_no
      @vid_bitrate = vid_bitrate
      @is_hq_audio = is_hq_audio
      @vid_height = vid_height
      @vid_fps = vid_fps
      @compressed_size_bytes = compressed_size_bytes
      @target_size_bytes = target_size_bytes
      build
    end

    def build
      tap do |box|
        box.hexpand = true
        box.append(separator)
        box.append(content_box)

        content_box.tap do |content|
          content.append(attempt_label)
          content.append(target_label)
          content.append(failure_box)

          failure_box.tap do |failure|
            failure.append(failure_icon)
            failure.append(failure_details_label)
          end
        end
      end
    end

    def separator
      @separator ||= Gtk::Separator.new(:horizontal).tap { |line| line.margin_top = 4 }
    end

    def content_box
      @content_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.margin_top = 6
        box.margin_end = 6
        box.margin_bottom = 6
        box.margin_start = 6
      end
    end

    def attempt_label
      @attempt_label ||= Gtk::Label.new(interpolate(_("Attempt {}"), @attempt_no)).tap do |label|
        label.xalign = 0
        label.margin_top = 4
        label.margin_bottom = 6
        label.add_css_class("heading")
      end
    end

    def target_label
      @target_label ||= Gtk::Label.new(target_text).tap do |label|
        label.xalign = 0
        label.margin_bottom = 12
        label.add_css_class("dimmed")
      end
    end

    def failure_box
      @failure_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.width_request = 300
      end
    end

    # An up arrow for an overshoot, a down arrow for an undershoot.
    def failure_icon
      @failure_icon ||= Gtk::Image.new.tap do |image|
        image.icon_size = :normal
        image.margin_end = 10
        image.icon_name = icon_name
      end
    end

    def failure_details_label
      @failure_details_label ||= Gtk::Label.new(failure_text).tap do |label|
        label.wrap = true
        label.wrap_mode = :word_char
        label.max_width_chars = 40
      end
    end

    private

      def too_large? = @compressed_size_bytes >= @target_size_bytes

      def icon_name
        if too_large?
          "arrow2-up-symbolic"
        else
          "arrow2-down-symbolic"
        end
      end

      def compressed_size_mb
        (@compressed_size_bytes / 1024.0 / 1024.0).round(1)
      end

      def failure_text
        interpolate(
          if too_large?
            _("Compressed file size was too large ({size}\u202F{unit})")
          else
            _("Compressed file size was too small ({size}\u202F{unit})")
          end,
          size: compressed_size_mb,
          unit: _("MiB"),
        )
      end

      # The same bitrate/resolution/audio summary the running attempt shows,
      # without its "Compressing to" lead-in.
      def target_text
        interpolate(
          _("{vid_br}\u202F{vid_br_unit} ({extra_details})"),
          vid_br:        @vid_bitrate / 1000,
          vid_br_unit:   _("kbps"),
          extra_details: Shared.res_fps_details(
            is_hq_audio: @is_hq_audio,
            vid_height:  @vid_height,
            vid_fps:     @vid_fps,
          ),
        )
      end
  end
end
