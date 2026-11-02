# frozen_string_literal: true

require "adwaita"

require_relative "shared"

module Constrict
  # Ported from upstream's src/progress_popover_box.blp and
  # src/progress_popover_box.py.
  #
  # The body of a source row's compression popover: the attempt currently
  # running at the top, and every attempt that has already failed listed
  # beneath it. It also assembles the one message a screen reader reads out
  # when the popover opens, since a popover full of labels is otherwise silent.
  class ProgressPopoverBox < Gtk::Box
    type_register

    attr_reader :top_widget, :fail_widgets

    def initialize(top_widget)
      super()
      self.orientation = :vertical
      @top_widget = top_widget
      @fail_widgets = []
      build
    end

    def build
      tap { |box| box.prepend(top_widget) }
    end

    # Every label in the popover, in reading order, joined into one
    # announcement.
    def message
      [
        top_widget.attempt_label.text,
        top_widget.progress_details_label.text,
        top_widget.target_details_label.text,
      ].concat(
        fail_widgets.flat_map do |fail_widget|
          [
            fail_widget.attempt_label.text,
            fail_widget.target_label.text,
            fail_widget.failure_details_label.text,
          ]
        end,
      ).join("... ")
    end

    # Swaps in a new widget at the top of the popover.
    def set_top_widget(widget, daemon)
      Shared.update_ui(daemon) do
        remove(@top_widget)
        prepend(widget)
      end

      @top_widget = widget
    end

    # Adds a failed attempt, directly below the running one, so the list reads
    # newest failure first.
    def add_fail_widget(fail_widget, daemon)
      @fail_widgets.push(fail_widget)

      Shared.update_ui(daemon) { insert_child_after(fail_widget, top_widget) }
    end
  end
end
