# frozen_string_literal: true

require "adwaita"

require_relative "shared"

module Constrict
  # Ported from upstream's src/sources_list_box.blp and
  # src/sources_list_box.py.
  #
  # The boxed list of queued videos, with an "Add Videos…" button row pinned to
  # the bottom. That button row is also the list's own length marker: its index
  # is the number of source rows above it.
  #
  # The list box owns how interactive its rows are. It is locked while a
  # compression is running, and even unlocked a single row cannot be dragged
  # and the first and last rows cannot be moved past the ends of the list.
  class SourcesListBox < Gtk::ListBox
    type_register

    attr_reader :locked

    def initialize
      super
      @locked = false
      build
    end

    def build
      tap do |list_box|
        list_box.selection_mode = :none
        list_box.add_css_class("boxed-list")
        list_box.append(add_videos_button)
      end
    end

    def add_videos_button
      @add_videos_button ||= Adwaita::ButtonRow.new.tap do |row|
        row.start_icon_name = "list-add-symbolic"
        row.title = "Add Vide_os…"
        row.use_underline = true
        row.action_name = "win.open"
      end
    end

    # Removing a row changes which rows can be moved where, so the whole list's
    # interactivity is refreshed after every removal.
    def remove(child)
      super
      update_rows(false)
    end

    # Clears the queue, keeping the button row the list is measured by.
    def remove_all
      super
      append(add_videos_button)
    end

    # Locks or unlocks the list and every row in it.
    def set_locked(locked, daemon)
      @locked = locked
      update_rows(daemon)
    end

    # The number of source rows, which is where the button row sits.
    def length = add_videos_button.index

    def any? = length.positive?

    def all
      length.times.map { |index| get_row_at_index(index) }
    end

    def add_sources(video_source_rows)
      length.then do |first_index|
        video_source_rows.each_with_index do |row, offset|
          insert(row, first_index + offset)
        end
      end

      update_rows(false)
    end

    # Moves a row to where another row currently sits.
    def move(source_row, dest_row)
      dest_row.index.then do |dest_index|
        remove(source_row)
        insert(source_row, dest_index)
      end

      update_rows(false)
    end

    def update_rows(daemon)
      all.then do |rows|
        rows.each_with_index do |row, index|
          update_row(
            row,
            index,
            rows.length,
            daemon,
          )
        end
      end
    end

    # A lone row has nowhere to be dragged to, so its handle is only a
    # decoration; the move actions are likewise disabled at the ends.
    def update_row(row, index, length, daemon)
      row.set_draggable(length > 1 && !locked)
      Shared.update_ui(daemon) { row.show_drag_handle(!locked) }

      row.set_action_enabled("move-up", index.positive? && !locked)
      row.set_action_enabled("move-down", index < (length - 1) && !locked)
      row.set_action_enabled("remove", !locked)
    end
  end
end
