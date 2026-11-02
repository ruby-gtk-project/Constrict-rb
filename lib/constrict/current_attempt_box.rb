# frozen_string_literal: true

require "adwaita"

require_relative "shared"

module Constrict
  # Ported from upstream's src/current_attempt_box.blp and
  # src/current_attempt_box.py.
  #
  # The box at the top of a source row's compression popover: which attempt is
  # running, what it is aiming for, a progress bar, and the percentage with an
  # estimate of the time left. Upstream's acknowledgement stands: the progress
  # bar and its surrounding text are modelled on Nautilus' progress info
  # widget.
  class CurrentAttemptBox < Gtk::Box
    type_register

    # Where the time estimate switches units. Taken, as upstream notes, from
    # Nautilus' file-operations code — including the four-hour mark past which
    # minutes stop being worth showing.
    MINUTE = 60
    HOUR = 60 * 60
    MINUTES_CUTOFF = 4 * HOUR

    def initialize
      super()
      self.orientation = :vertical
      build
    end

    def build
      tap do |box|
        box.margin_start = 6
        box.margin_end = 6
        box.margin_top = 6
        box.margin_bottom = 6
        box.hexpand = true

        box.append(attempt_label)
        box.append(target_details_label)
        box.append(progress_bar)
        box.append(progress_details_label)
      end
    end

    # Read back by the popover box when it assembles its screen-reader message.
    def attempt_label
      @attempt_label ||= Gtk::Label.new("Attempt 1").tap do |label|
        label.xalign = 0
        label.margin_bottom = 6
        label.add_css_class("heading")
      end
    end

    def target_details_label
      @target_details_label ||= Gtk::Label.new("Initializing…").tap do |label|
        label.width_request = 300
        label.margin_bottom = 6
        label.hexpand = true
        label.ellipsize = :start
        label.max_width_chars = 40
        label.xalign = 0
      end
    end

    def progress_bar
      @progress_bar ||= Gtk::ProgressBar.new.tap do |bar|
        bar.valign = :center
        bar.width_request = 300
        bar.hexpand = true
        bar.margin_bottom = 4
        bar.margin_start = 2
      end
    end

    def progress_details_label
      @progress_details_label ||= Gtk::Label.new("0 %").tap do |label|
        label.wrap = true
        label.wrap_mode = :word_char
        label.ellipsize = :end
        label.xalign = 0
        label.add_css_class("dim-label")
        label.add_css_class("numeric")
      end
    end

    # Sets the text above the progress bar directly, for the states that have
    # no percentage to show yet (VP9's unreported first pass).
    def set_progress_text(text, daemon)
      Shared.update_ui(daemon) { progress_details_label.text = text }
    end

    # Pulses the progress bar in activity mode. Upstream pulses on the main
    # thread whatever the daemon flag says, because a pulse queued through
    # idle_add arrives too late to animate smoothly.
    def pulse_progress(_daemon)
      progress_bar.pulse
    end

    # Names the attempt and what it is encoding to: the video bitrate, the
    # resolution and framerate, and whether the audio survived at high or low
    # quality. `is_hq_audio` is nil for a video with no audio at all.
    def set_attempt_details(
      attempt_no:,
      vid_bitrate:,
      is_hq_audio:,
      vid_height:,
      vid_fps:,
      daemon:
    )
      Shared.update_ui(daemon) do
        attempt_label.label = "Attempt #{attempt_no}"
        target_details_label.label = target_string(
          vid_bitrate: vid_bitrate,
          is_hq_audio: is_hq_audio,
          vid_height:  vid_height,
          vid_fps:     vid_fps,
        )
      end
    end

    # Moves the progress bar and writes the percentage, with an estimate of the
    # time remaining when there is one. `seconds_left` is nil before the first
    # estimate is reliable, and -1 once the encode is on its last frames.
    def set_progress(fraction, seconds_left, daemon)
      Shared.update_ui(daemon) do
        progress_bar.fraction = fraction
        progress_details_label.label = progress_string(fraction, seconds_left)
      end
    end

    private

      def target_string(vid_bitrate:, is_hq_audio:, vid_height:, vid_fps:)
        extra = Shared.res_fps_details(
          is_hq_audio: is_hq_audio,
          vid_height:  vid_height,
          vid_fps:     vid_fps,
        )

        "Compressing to #{vid_bitrate / 1000} kbps (#{extra})"
      end

      def progress_string(fraction, seconds_left)
        percentage_text = "#{(fraction * 100).round} %"

        if seconds_left.nil?
          percentage_text
        elsif seconds_left == -1
          "#{percentage_text} — Almost done"
        else
          "#{percentage_text} — About #{time_left(seconds_left)} left"
        end
      end

      def time_left(seconds_left)
        if seconds_left < MINUTE
          plural(seconds_left, "second", "seconds")
        elsif seconds_left < HOUR
          plural(seconds_left / MINUTE, "minute", "minutes")
        elsif seconds_left < MINUTES_CUTOFF
          [
            plural(seconds_left / HOUR, "hour", "hours"),
            plural((seconds_left / MINUTE) % 60, "minute", "minutes"),
          ].join(", ")
        else
          plural(seconds_left / HOUR, "hour", "hours")
        end
      end

      def plural(count, singular, many)
        if count == 1
          "#{count} #{singular}"
        else
          "#{count} #{many}"
        end
      end
  end
end
