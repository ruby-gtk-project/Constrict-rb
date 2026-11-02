# frozen_string_literal: true

require "adwaita"

module Constrict
  # Ported from upstream's src/progress_pie.py.
  #
  # A circular progress indicator shown in a source row while its video is
  # being compressed. Upstream's acknowledgement stands: the design comes from
  # GNOME Builder's IdeProgressIcon, written in C by Christian Hergert.
  #
  # The pie draws in the widget's own foreground colour, so it follows the
  # theme: the full circle at 15% alpha for the track, and the filled wedge at
  # the colour's own alpha on top.
  class ProgressPie < Gtk::DrawingArea
    type_register

    BACKGROUND_ALPHA = 0.15

    attr_reader :fraction

    def initialize
      super
      @fraction = 0.0
      build
    end

    def build
      tap do |pie|
        pie.valign = :center
        pie.halign = :center
        pie.set_draw_func { |_, context, width, height| draw(context, width, height) }
        pie.queue_draw
      end
    end

    # Updates the pie to show a new progress fraction.
    def fraction=(value)
      @fraction = value
      queue_draw
    end

    private

      def draw(context, width, height)
        color.then do |rgba|
          radius = width / 2.0

          context.set_source_rgba(
            rgba.red,
            rgba.green,
            rgba.blue,
            BACKGROUND_ALPHA,
          )
          context.arc(
            width / 2.0,
            height / 2.0,
            radius,
            0.0,
            2 * Math::PI,
          )
          context.fill

          if fraction > 0.0
            context.set_source_rgba(
              rgba.red,
              rgba.green,
              rgba.blue,
              rgba.alpha,
            )
            context.arc(
              width / 2.0,
              height / 2.0,
              radius,
              -0.5 * Math::PI,
              (2 * fraction * Math::PI) - (0.5 * Math::PI),
            )

            # A partial wedge is closed back through the centre; a full circle
            # needs no closing lines, and drawing them would leave a seam.
            if fraction != 1.0
              context.line_to(width / 2.0, height / 2.0)
              context.line_to(width / 2.0, 0)
            end

            context.fill
          end
        end
      end
  end
end
