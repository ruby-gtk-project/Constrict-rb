# frozen_string_literal: true

require "adwaita"

require_relative "i18n"
require_relative "shared"

module Constrict
  # Ported from upstream's src/error_dialog.blp and src/error_dialog.py.
  #
  # Shows the ffmpeg output behind a failed compression in a monospace text
  # view, with a button that copies it to the clipboard and confirms with a
  # toast. The text view is read-only: it is there to be read and copied.
  class ErrorDialog < Adwaita::Dialog
    include I18n

    type_register

    def initialize(video_name, error_details)
      super()
      @video_name = video_name
      @error_details = error_details
      build
    end

    def build
      tap do |dialog|
        dialog.title = _("Compression Error")
        dialog.content_width = 600
        dialog.content_height = 450
        dialog.child = toolbar_view
        dialog.insert_action_group("dialog", action_group)

        toolbar_view.tap do |view|
          view.add_top_bar(Adwaita::HeaderBar.new)
          view.content = toast_overlay
        end

        toast_overlay.tap { |overlay| overlay.child = preference_page }

        preference_page.tap { |page| page.add(details_group) }

        details_group.tap do |group|
          group.header_suffix = copy_button
          group.add(scrolled_window)
        end

        scrolled_window.tap { |window| window.child = text_view }
      end
    end

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new

    def preference_page
      @preference_page ||= Adwaita::PreferencesPage.new.tap do |page|
        page.description = interpolate(
          _("There was a problem compressing “{}”"),
          Shared.markup_escape(@video_name),
        )
      end
    end

    def details_group
      @details_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Details")
      end
    end

    def copy_button
      @copy_button ||= Gtk::Button.new.tap do |button|
        button.tooltip_text = _("Copy Details")
        button.icon_name = "edit-copy-symbolic"
        button.valign = :center
        button.action_name = "dialog.copy-details"
        button.add_css_class("flat")
      end
    end

    def scrolled_window
      @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |window|
        window.vexpand = true
        window.overflow = :hidden
        window.add_css_class("card")
      end
    end

    def text_view
      @text_view ||= Gtk::TextView.new.tap do |view|
        view.editable = false
        view.wrap_mode = :word_char
        view.top_margin = 12
        view.bottom_margin = 12
        view.left_margin = 12
        view.right_margin = 12
        view.monospace = true
        view.add_css_class("monospace")
        view.add_css_class("inline")
        view.buffer.text = @error_details
      end
    end

    # Upstream installs the action on the widget class with
    # gtk_widget_class_install_action, which the Ruby bindings do not expose;
    # an action group inserted under the same "dialog" prefix gives the button
    # the same `dialog.copy-details` name to point at.
    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        group.add_action(
          Gio::SimpleAction.new("copy-details").tap do |action|
            action.signal_connect("activate") { copy_details }
          end,
        )
      end
    end

    private

      def copy_details
        clipboard.set(text_view.buffer.text)
        toast_overlay.add_toast(Adwaita::Toast.new(_("Details copied to clipboard")))
      end
  end
end
