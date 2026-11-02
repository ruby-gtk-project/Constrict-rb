# frozen_string_literal: true

require "adwaita"

require_relative "constrict_utils"
require_relative "current_attempt_box"
require_relative "drag_overlay"
require_relative "enums"
require_relative "error_dialog"
require_relative "i18n"
require_relative "shared"
require_relative "sources_list_box"
require_relative "sources_row"

module Constrict
  # Ported from upstream's src/window.blp and src/window.py.
  #
  # The main window. It has two faces, switched by a view stack: an empty state
  # inviting the first video in, and the queue page — the compression settings
  # in a collapsible sidebar, the list of queued videos in the content pane,
  # and an export or cancel bar along the bottom.
  #
  # The window also owns the compression run itself: it reads its settings,
  # walks the queue on a background thread, and feeds each row's progress,
  # failed attempts, errors and completion back through the callbacks the
  # backend calls.
  class ConstrictWindow < Adwaita::ApplicationWindow
    include I18n

    type_register

    STATUS_PAGE = "status_page"
    QUEUE_PAGE = "queue_page"

    # The framerate a bitrate too low to carry more gets capped to, quoted by
    # the framerate help popover. ConstrictUtils caps at the same number.
    FPS_FLOOR = 24

    # Videos, plus animated GIFs, which ffmpeg treats as video too.
    VIDEO_MIME_PREFIX = "video/"
    GIF_MIME_TYPE = "image/gif"

    attr_reader :settings

    # `application` is the Constrict::Application, which the window asks for
    # settings and for the application-level services below. A type-registered
    # subclass cannot take its parent's positional constructor argument, so
    # the GtkApplication it wraps is set as the property that backs instead.
    def initialize(application)
      super()
      self.application = application.app
      @application = application
      @settings = application.settings
      @compressing = false
      @currently_processed = ""
      build
    end

    def build
      tap do |window|
        window.title = _("Constrict")
        window.set_default_size(@settings["window-width"], @settings["window-height"])
        window.width_request = 360
        window.height_request = 294
        window.content = toast_overlay
        window.add_breakpoint(window_breakpoint)

        if @settings["window-maximized"]
          window.maximize
        end

        window_actions.each { |name, group| window.add_action(group) }

        toast_overlay.tap { |overlay| overlay.child = view_stack }

        view_stack.tap do |stack|
          stack.add_named(status_toolbar_view, STATUS_PAGE)
          stack.add_named(split_view, QUEUE_PAGE)
        end

        build_status_page
        build_queue_page
        connect_settings_controls
        apply_saved_settings

        window.signal_connect("close-request") { on_close_request }
      end
    end

    # --- Layout -------------------------------------------------------------

    def build_status_page
      status_toolbar_view.tap do |view|
        view.add_top_bar(status_header_bar)
        view.content = status_overlay

        status_header_bar.tap do |bar|
          bar.title_widget = Adwaita::WindowTitle.new(_("Constrict"), "")
          bar.pack_end(primary_menu_button)
        end

        status_overlay.tap do |overlay|
          overlay.child = status_drag_overlay
          overlay.add_overlay(status_progress_bar)
        end

        status_drag_overlay.tap do |drag_overlay|
          drag_overlay.child = status_page
          drag_overlay.drop_target = status_drop_target
        end

        status_page.tap do |page|
          page.child = open_button
          page.add_controller(status_drop_target)
        end
      end
    end

    def build_queue_page
      split_view.tap do |view|
        view.sidebar = sidebar_toolbar_view
        view.content = content_toolbar_view
        view.min_sidebar_width = 300
        view.max_sidebar_width = 360
        view.bind_property(
          "show-sidebar",
          show_sidebar_button,
          "active",
          :bidirectional,
        )
      end

      build_sidebar
      build_content_pane
    end

    def build_sidebar
      sidebar_toolbar_view.tap do |view|
        view.add_top_bar(sidebar_header_bar)
        view.content = settings_page

        sidebar_header_bar.tap do |bar|
          bar.title_widget = Adwaita::WindowTitle.new(_("Constrict"), "")
          bar.pack_end(sidebar_menu_button)
        end

        settings_page.tap do |page|
          page.add(target_size_group)
          page.add(fps_group)
          page.add(encoding_group)
          page.add(advanced_group)

          target_size_group.tap { |group| group.add(target_size_row) }

          fps_group.tap do |group|
            group.header_suffix = fps_help_button
            group.add(auto_row)
            group.add(clear_row)
            group.add(smooth_row)
          end

          encoding_group.tap do |group|
            group.header_suffix = enc_options_help_button
            group.add(codec_dropdown)
            group.add(extra_quality_toggle)
          end

          advanced_group.tap do |group|
            group.header_suffix = adv_options_help_button
            group.add(tolerance_row)
          end
        end
      end
    end

    def build_content_pane
      content_toolbar_view.tap do |view|
        view.add_top_bar(content_header_bar)
        view.content = content_box
        view.add_bottom_bar(export_bar)
        view.add_bottom_bar(cancel_bar)

        content_header_bar.tap do |bar|
          bar.title_widget = main_view_title
          bar.pack_start(show_sidebar_button)
        end

        content_box.tap do |box|
          box.append(warning_banner)
          box.append(queue_overlay)
        end

        queue_overlay.tap do |overlay|
          overlay.child = queue_drag_overlay
          overlay.add_overlay(queue_page_progress_bar)
        end

        queue_drag_overlay.tap do |drag_overlay|
          drag_overlay.child = queue_page
          drag_overlay.drop_target = drop_target_queue
          drag_overlay.add_controller(drop_target_queue)
        end

        queue_page.tap do |page|
          page.add(sources_group)

          sources_group.tap do |group|
            group.header_suffix = clear_all_button
            group.add(sources_list_box)
          end
        end

        export_bar.tap { |bar| bar.set_center_widget(export_button) }
        cancel_bar.tap { |bar| bar.set_center_widget(cancel_button) }
      end
    end

    # --- Widgets ------------------------------------------------------------

    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
    def view_stack = @view_stack ||= Adwaita::ViewStack.new
    def status_toolbar_view = @status_toolbar_view ||= Adwaita::ToolbarView.new
    def status_header_bar = @status_header_bar ||= Adwaita::HeaderBar.new
    def status_overlay = @status_overlay ||= Gtk::Overlay.new
    def status_drag_overlay = @status_drag_overlay ||= DragOverlay.new
    def sidebar_toolbar_view = @sidebar_toolbar_view ||= Adwaita::ToolbarView.new
    def sidebar_header_bar = @sidebar_header_bar ||= Adwaita::HeaderBar.new
    def content_toolbar_view = @content_toolbar_view ||= Adwaita::ToolbarView.new
    def content_header_bar = @content_header_bar ||= Adwaita::HeaderBar.new
    def queue_overlay = @queue_overlay ||= Gtk::Overlay.new
    def queue_drag_overlay = @queue_drag_overlay ||= DragOverlay.new
    def settings_page = @settings_page ||= Adwaita::PreferencesPage.new
    def queue_page = @queue_page ||= Adwaita::PreferencesPage.new
    def target_size_group = @target_size_group ||= Adwaita::PreferencesGroup.new
    def sources_list_box = @sources_list_box ||= SourcesListBox.new
    def main_view_title = @main_view_title ||= Adwaita::WindowTitle.new(_("Constrict"), "")

    # Collapses the sidebar over the content, rather than beside it, once the
    # window is too narrow to show both.
    def window_breakpoint
      @window_breakpoint ||= Adwaita::Breakpoint.new(
        Adwaita::BreakpointCondition.parse("max-width: 750sp"),
      ).tap do |breakpoint|
        breakpoint.add_setter(split_view, "collapsed", true)
        breakpoint.add_setter(split_view, "max-sidebar-width", 300)
        breakpoint.add_setter(show_sidebar_button, "visible", true)
        breakpoint.add_setter(window_actions.fetch("toggle-sidebar"), "enabled", true)
      end
    end

    def split_view
      @split_view ||= Adwaita::OverlaySplitView.new
    end

    def content_box = @content_box ||= Gtk::Box.new(:vertical, 0)

    def status_page
      @status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = "video-encoder-symbolic"
        page.title = _("Compress Videos")
        page.description = _("Drag and drop videos here")
        page.add_css_class("drop-widget")
      end
    end

    def open_button
      @open_button ||= Gtk::Button.new.tap do |button|
        button.label = _("_Open…")
        button.use_underline = true
        button.action_name = "win.open"
        button.can_shrink = true
        button.halign = :center
        button.add_css_class("pill")
        button.add_css_class("suggested-action")
      end
    end

    # One progress bar per page, both driven by #progress= while videos are
    # being staged.
    def status_progress_bar = @status_progress_bar ||= osd_progress_bar
    def queue_page_progress_bar = @queue_page_progress_bar ||= osd_progress_bar

    def primary_menu_button = @primary_menu_button ||= menu_button
    def sidebar_menu_button = @sidebar_menu_button ||= menu_button

    def primary_menu
      @primary_menu ||= Gio::Menu.new.tap do |menu|
        menu.append_section(
          nil,
          Gio::Menu.new.tap { |section| section.append(_("_New Window"), "app.new-window") },
        )
        menu.append_section(
          nil,
          Gio::Menu.new.tap do |section|
            section.append(_("_Preferences"), "app.preferences")
            section.append(_("_Keyboard Shortcuts"), "app.shortcuts")
            section.append(_("_About Constrict"), "app.about")
          end,
        )
      end
    end

    def show_sidebar_button
      @show_sidebar_button ||= Gtk::ToggleButton.new.tap do |button|
        button.icon_name = "sidebar-show-symbolic"
        button.tooltip_text = _("Toggle Settings Pane")
        button.active = true
        button.visible = false
      end
    end

    def warning_banner
      @warning_banner ||= Adwaita::Banner.new(
        _("Issues with video sources — fix before compressing"),
      )
    end

    def sources_group
      @sources_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Video Sources")
      end
    end

    def clear_all_button
      @clear_all_button ||= Gtk::Button.new.tap do |button|
        button.label = _("_Clear All")
        button.use_underline = true
        button.action_name = "win.clear_all"
        button.valign = :center
        button.add_css_class("flat")
      end
    end

    def export_bar = @export_bar ||= Gtk::ActionBar.new

    def cancel_bar
      @cancel_bar ||= Gtk::ActionBar.new.tap { |bar| bar.visible = false }
    end

    def export_button
      @export_button ||= pill_button("_Export To…", "win.export").tap do |button|
        button.add_css_class("suggested-action")
      end
    end

    def cancel_button = @cancel_button ||= pill_button("_Cancel…", "win.cancel")

    # --- Compression settings ----------------------------------------------

    def target_size_input
      @target_size_input ||= Gtk::Adjustment.new(
        10,
        1,
        999_999,
        1,
        10,
        0,
      )
    end

    def target_size_row
      @target_size_row ||= Adwaita::SpinRow.new(target_size_input, 1, 0).tap do |row|
        row.title = interpolate(_("Target _Size ({})"), _("MiB"))
        row.use_underline = true
        row.numeric = true
      end
    end

    def fps_group
      @fps_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Framerate Limit")
      end
    end

    def auto_row
      @auto_row ||= check_row(
        _("_Automatic"),
        _("Use the highest framerate without sacrificing resolution"),
        auto_check_button,
      )
    end

    def clear_row
      @clear_row ||= check_row(
        fps_title("_30"),
        _("Ensure higher image clarity"),
        clear_check_button,
      )
    end

    def smooth_row
      @smooth_row ||= check_row(
        fps_title("_60"),
        _("Ensure smoother motion"),
        smooth_check_button,
      )
    end

    # The framerate rows share one msgid, so that "FPS" is translated once for
    # both. The mnemonic underscore travels with the number upstream puts in
    # the placeholder.
    def fps_title(value)
      interpolate(_("{}\u202FFPS"), value)
    end

    def auto_check_button
      @auto_check_button ||= Gtk::CheckButton.new.tap do |button|
        button.active = true
        button.valign = :center
      end
    end

    def clear_check_button = @clear_check_button ||= grouped_check_button
    def smooth_check_button = @smooth_check_button ||= grouped_check_button

    def encoding_group
      @encoding_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Encoding Options")
      end
    end

    # The dropdown's indices are the Constrict::VideoCodec values, which is why
    # the order of these strings matters.
    def codec_dropdown
      @codec_dropdown ||= Adwaita::ComboRow.new.tap do |row|
        row.title = _("_Video Codec")
        row.use_underline = true
        row.model = Gtk::StringList.new(["H.264", "H.265 (HEVC)", "AV1", "VP9"])
      end
    end

    def extra_quality_toggle
      @extra_quality_toggle ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = _("Extra _Quality")
        row.use_underline = true
        row.subtitle = _("Increase image quality at the cost of compression time")
      end
    end

    def advanced_group
      @advanced_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Advanced Options")
      end
    end

    def tolerance_input
      @tolerance_input ||= Gtk::Adjustment.new(
        10,
        5,
        100,
        1,
        10,
        0,
      )
    end

    def tolerance_row
      @tolerance_row ||= Adwaita::SpinRow.new(tolerance_input, 1, 0).tap do |row|
        row.title = _("_Tolerance (%)")
        row.use_underline = true
        row.subtitle = _("How far end file sizes can be below target")
        row.numeric = true
      end
    end

    # --- Help popovers ------------------------------------------------------

    def fps_help_button = @fps_help_button ||= help_button(fps_help_popover)
    def fps_help_popover = @fps_help_popover ||= help_popover(fps_help_label)

    def fps_help_label
      @fps_help_label ||= help_label(
        interpolate(
          _(
            "Videos compressed to low bitrates may be capped to " \
            "{}\u202FFPS, regardless of the option set.",
          ),
          FPS_FLOOR,
        ),
      )
    end

    def enc_options_help_button
      @enc_options_help_button ||= help_button(enc_options_help_popover)
    end

    def enc_options_help_popover
      @enc_options_help_popover ||= help_popover(enc_options_help_label)
    end

    def enc_options_help_label
      @enc_options_help_label ||= help_label(
        _(
          "H.264 is recommended for resolutions up to 1080p.\n\nH.265 " \
          "(HEVC), AV1, and VP9, are optimized for resolutions of 1080p and " \
          "higher.",
        ),
      )
    end

    def adv_options_help_button
      @adv_options_help_button ||= help_button(adv_options_help_popover)
    end

    def adv_options_help_popover
      @adv_options_help_popover ||= help_popover(adv_options_help_label)
    end

    def adv_options_help_label
      @adv_options_help_label ||= help_label(
        interpolate(
          _(
            "Decreasing the tolerance maximizes image quality by reducing " \
            "how much compressed file sizes can be under target. However, " \
            "this can increase the number of attempts needed to meet the " \
            "target, increasing compression time. A tolerance of " \
            "{}\u202F% or more is recommended.",
          ),
          @settings.default_value("tolerance"),
        ),
      ).tap { |label| label.max_width_chars = 50 }
    end

    # --- Drop targets -------------------------------------------------------

    def status_drop_target = @status_drop_target ||= file_drop_target
    def drop_target_queue = @drop_target_queue ||= file_drop_target

    # --- Actions ------------------------------------------------------------

    # The window's own actions, under the `win.` prefix. `toggle-sidebar` starts
    # disabled: there is nothing to toggle until the breakpoint collapses the
    # split view, which is what enables it.
    def window_actions
      @window_actions ||= {
        "toggle-sidebar" => action("toggle-sidebar", enabled: false) { toggle_sidebar },
        "open"           => action("open") { open_file_dialog },
        "export"         => action("export", enabled: false) { export_file_dialog },
        "cancel"         => action("cancel") { show_cancel_dialog(false) },
        "clear_all"      => action("clear_all") { delist_all },
        "close"          => action("close") { close },
      }
    end

    def window_action(name) = window_actions.fetch(name)

    # --- Settings -----------------------------------------------------------

    def target_size = target_size_input.value.to_i
    def tolerance = tolerance_input.value.to_i
    def video_codec = codec_dropdown.selected
    def extra_quality = extra_quality_toggle.active?

    def fps_mode
      if clear_check_button.active?
        FpsMode::PREFER_CLEAR
      elsif smooth_check_button.active?
        FpsMode::PREFER_SMOOTH
      else
        FpsMode::AUTO
      end
    end

    def fps_mode=(mode)
      case mode
      when FpsMode::PREFER_CLEAR then clear_check_button.active = true
      when FpsMode::PREFER_SMOOTH then smooth_check_button.active = true
      else auto_check_button.active = true
      end
    end

    # Writes the window's geometry and compression settings back, so the next
    # window opens on the same ones.
    def save_window_state
      @settings["window-maximized"] = maximized?
      @settings["window-width"] = default_width
      @settings["window-height"] = default_height
      @settings["target-size"] = target_size
      @settings.fps_mode = fps_mode
      @settings.video_codec = video_codec
      @settings["extra-quality"] = extra_quality
      @settings["tolerance"] = tolerance
    end

    # --- Queue --------------------------------------------------------------

    # Adds videos to the queue: directories are walked, files already queued
    # and files that are not video are skipped, and anything left over is
    # reported as an unknown format.
    def stage_videos(video_list)
      flatten_files(video_list).then do |files|
        existing_paths = sources_list_box.all.map { |row| host_path(row.video_path) }
        unsupported_mimes = []
        staged_rows = []

        files.each_with_index do |file, index|
          stage_video(file, existing_paths, unsupported_mimes).then do |row|
            if row
              staged_rows.push(row)
            end
          end

          self.progress = (index + 1).to_f / files.length
        end

        self.progress = 0.0

        unsupported_mimes.uniq.each do |mime|
          toast_overlay.add_toast(
            Adwaita::Toast.new(
              interpolate(_("Unknown video format “{}”"), mime),
            ),
          )
        end

        sources_list_box.add_sources(staged_rows)

        unless staged_rows.empty?
          view_stack.visible_child_name = QUEUE_PAGE
          refresh_can_export(false)
          staged_rows.last.grab_focus
          set_queued_title(false)
        end
      end
    end

    # Removes a row and brings the title, the export action and the view stack
    # back in line with what is left.
    def remove_row(row)
      sources_list_box.remove(row)
      refresh_can_export(false)
      set_queued_title(false)
    end

    def delist_all
      sources_list_box.remove_all
      refresh_can_export(false)
      set_queued_title(false)
    end

    # Re-reads every row's preview, which is also what re-checks whether each
    # video suits the current target size.
    def refresh_previews
      sources_list_box.all.each do |row|
        row.set_preview(-> { target_size }, -> { fps_mode }, false)
      end

      refresh_can_export(false)
      withdraw_complete_notification
    end

    # Enables or disables exporting from the states of the queued videos: a
    # broken or incompatible video blocks it, and so does a queue where
    # everything is already done.
    def refresh_can_export(daemon)
      sources_list_box.all.then do |sources|
        if sources.empty?
          Shared.update_ui(daemon) do
            window_action("export").enabled = false
            warning_banner.revealed = false
            view_stack.visible_child_name = STATUS_PAGE

            if split_view.collapsed?
              split_view.show_sidebar = false
            end
          end
        else
          refresh_can_export_for(sources, daemon)
        end
      end
    end

    # Shows the warning banner and blocks exporting.
    def set_warning_state(is_error, daemon)
      Shared.update_ui(daemon) do
        window_action("export").enabled = !is_error
        warning_banner.revealed = is_error

        if is_error
          announce(
            warning_banner.title,
            Gtk::AccessibleAnnouncementPriority::MEDIUM,
          )
        end
      end
    end

    # --- Titles -------------------------------------------------------------

    def set_queued_title(daemon)
      sources_list_box.all.then do |sources|
        self.title = queued_title(sources)

        Shared.update_ui(daemon) do
          main_view_title.title = title
          main_view_title.subtitle = ""
        end
      end
    end

    def set_compressing_title(current_index, export_dir)
      sources_list_box.all.then do |sources|
        self.title = compressing_title(sources, current_index)

        main_view_title.title = title
        main_view_title.subtitle = interpolate(_("Exporting to {}"), export_dir)
      end
    end

    # --- Progress bars ------------------------------------------------------

    def progress=(fraction)
      status_progress_bar.fraction = fraction
      queue_page_progress_bar.fraction = fraction
    end

    private

      def osd_progress_bar
        Gtk::ProgressBar.new.tap do |bar|
          bar.valign = :start
          bar.add_css_class("osd")
        end
      end

      def menu_button
        Gtk::MenuButton.new.tap do |button|
          button.primary = true
          button.icon_name = "open-menu-symbolic"
          button.tooltip_text = _("Main Menu")
          button.menu_model = primary_menu
        end
      end

      def pill_button(label, action_name)
        Gtk::Button.new.tap do |button|
          button.label = label
          button.use_underline = true
          button.action_name = action_name
          button.halign = :center
          button.margin_top = 6
          button.margin_bottom = 6
          button.add_css_class("pill")
        end
      end

      def grouped_check_button
        Gtk::CheckButton.new.tap do |button|
          button.group = auto_check_button
          button.valign = :center
        end
      end

      def check_row(title, subtitle, check_button)
        Adwaita::ActionRow.new.tap do |row|
          row.title = title
          row.use_underline = true
          row.subtitle = subtitle
          row.add_prefix(check_button)
          row.activatable_widget = check_button
        end
      end

      def help_label(text)
        Gtk::Label.new(text).tap do |label|
          label.halign = :center
          label.margin_start = 6
          label.margin_end = 6
          label.margin_top = 6
          label.margin_bottom = 6
          label.wrap = true
          label.max_width_chars = 30
          label.valign = :center
        end
      end

      # Each help popover announces its own text when it opens, since a
      # popover of static text is otherwise invisible to a screen reader.
      def help_popover(label)
        Gtk::Popover.new.tap do |popover|
          popover.child = label
          popover.signal_connect("show") do
            announce(label.text, Gtk::AccessibleAnnouncementPriority::MEDIUM)
          end
        end
      end

      def help_button(popover)
        Gtk::MenuButton.new.tap do |button|
          button.icon_name = "help-about-symbolic"
          button.tooltip_text = _("More Information")
          button.popover = popover
          button.add_css_class("flat")
        end
      end

      def file_drop_target
        Gtk::DropTarget.new(Gdk::FileList.gtype, :copy).tap do |target|
          target.signal_connect("drop") do |_, value, _x, _y|
            Thread.new { stage_videos(value.files) }
            true
          end
        end
      end

      def action(name, enabled: true)
        Gio::SimpleAction.new(name).tap do |simple_action|
          simple_action.enabled = enabled
          simple_action.signal_connect("activate") { yield }
        end
      end

      def toggle_sidebar
        if view_stack.visible_child_name == QUEUE_PAGE
          split_view.show_sidebar = !split_view.show_sidebar?
        end
      end

      # Every settings control refreshes the previews, because every one of
      # them can change the resolution a video will end up at. A check button
      # being switched off is the other half of another being switched on, so
      # only the activation is acted on.
      def connect_settings_controls
        target_size_input.signal_connect("value-changed") { refresh_previews }
        tolerance_input.signal_connect("value-changed") { refresh_previews }
        codec_dropdown.signal_connect("notify::selected") { refresh_previews }
        extra_quality_toggle.signal_connect("notify::active") { refresh_previews }

        [auto_check_button, clear_check_button, smooth_check_button].each do |button|
          button.signal_connect("toggled") do
            if button.active?
              refresh_previews
            end
          end
        end
      end

      def apply_saved_settings
        target_size_input.value = @settings["target-size"]
        tolerance_input.value = @settings["tolerance"]
        extra_quality_toggle.active = @settings["extra-quality"]
        codec_dropdown.selected = @settings.video_codec
        self.fps_mode = @settings.fps_mode
      end

      def refresh_can_export_for(sources, daemon)
        blocked = sources.any? do |video|
          [SourceState::BROKEN, SourceState::INCOMPATIBLE].include?(video.state)
        end

        if blocked
          set_warning_state(true, daemon)
        else
          set_warning_state(false, daemon)

          all_complete = sources.all? do |video|
            video.state == SourceState::COMPLETE
          end

          if all_complete
            Shared.update_ui(daemon) { window_action("export").enabled = false }
          end
        end
      end

      def queued_title(sources)
        if sources.empty?
          _("Constrict")
        elsif sources.length == 1
          interpolate(_("“{}” Queued"), sources.first.display_name)
        else
          interpolate(
            ngettext("{} Video Queued", "{} Videos Queued", sources.length),
            sources.length,
          )
        end
      end

      def compressing_title(sources, current_index)
        if sources.length == 1
          interpolate(_("Processing “{}”"), sources.first.display_name)
        else
          interpolate(
            ngettext(
              "{index}/{total} Video Processed",
              "{index}/{total} Videos Processed",
              sources.length,
            ),
            index: current_index,
            total: sources.length,
          )
        end
      end

      # Locks the controls a compression run must not have changed under it.
      def set_controls_lock(is_locked, daemon)
        Shared.update_ui(daemon) do
          [
            target_size_row,
            auto_row,
            clear_row,
            smooth_row,
            codec_dropdown,
            extra_quality_toggle,
            tolerance_row,
          ].each { |widget| widget.sensitive = !is_locked }
        end

        ["clear_all", "open", "export"].each do |name|
          window_action(name).enabled = !is_locked
        end

        sources_list_box.set_locked(is_locked, daemon)

        drag_action = :copy
        if is_locked
          drag_action = :none
        end

        drop_target_queue.actions = drag_action
      end

      def show_cancel_button(is_compressing, daemon)
        Shared.update_ui(daemon) do
          cancel_bar.visible = is_compressing
          export_bar.visible = !is_compressing
        end
      end

      # --- Dialogs ----------------------------------------------------------

      def open_file_dialog
        Gtk::FileDialog.new.tap do |dialog|
          dialog.title = _("Pick Videos")
          dialog.default_filter = video_filter

          initial_folder(@settings["open-initial-folder"]).then do |folder|
            if folder
              dialog.initial_folder = folder
            end
          end

          dialog.open_multiple(self) do |_, result|
            on_open_response(dialog, result)
          end
        end
      end

      def video_filter
        Gtk::FileFilter.new.tap do |filter|
          filter.name = _("Videos")
          filter.add_mime_type("video/*")
          filter.add_mime_type(GIF_MIME_TYPE)
        end
      end

      def on_open_response(dialog, result)
        dialog.open_multiple_finish(result).then do |files|
          unless files.nil? || files.empty?
            @settings["open-initial-folder"] = files.first.parent.path
            Thread.new { stage_videos(files) }
          end
        end
      rescue GLib::Error
        nil
      end

      def export_file_dialog
        Gtk::FileDialog.new.tap do |dialog|
          initial_folder(@settings["export-initial-folder"]).then do |folder|
            if folder
              dialog.initial_folder = folder
            end
          end

          dialog.select_folder(self) do |_, result|
            on_export_response(dialog, result)
          end
        end
      end

      def on_export_response(dialog, result)
        dialog.select_folder_finish(result).then do |folder|
          if folder
            @settings["export-initial-folder"] = folder.path
            Thread.new { bulk_compress(folder.path) }
          end
        end
      rescue GLib::Error
        nil
      end

      def initial_folder(path)
        unless path.to_s.empty?
          Gio::File.new_for_path(path)
        end
      end

      # Stopping a run throws away everything the current attempt has encoded,
      # so it is always confirmed.
      def show_cancel_dialog(quit_on_stop)
        Adwaita::AlertDialog.new(
          _("Stop Compression?"),
          interpolate(
            _("Progress made compressing “{}” will be permanently lost"),
            @currently_processed,
          ),
        ).tap do |dialog|
          dialog.add_response("cancel", _("_Cancel"))
          dialog.add_response("stop", _("_Stop"))
          dialog.set_response_appearance("stop", :destructive)

          dialog.choose(self) do |_, result|
            on_cancel_response(dialog, result, quit_on_stop)
          end
        end
      end

      def on_cancel_response(dialog, result, quit_on_stop)
        if dialog.choose_finish(result) == "stop"
          @compressing = false

          if quit_on_stop
            close
          end
        end
      end

      def error_dialog(file_name, error_details)
        ErrorDialog.new(file_name, error_details).present(self)
      end

      # Closing while a compression is running asks first, and the close is
      # finished by the dialog rather than here.
      def on_close_request
        if @compressing
          show_cancel_dialog(true)
          true
        else
          withdraw_complete_notification
          save_window_state
          false
        end
      end

      # --- Notifications ----------------------------------------------------

      def complete_notification_id = "compress-complete-#{id}"

      def withdraw_complete_notification
        @application.withdraw_notification(complete_notification_id)
      end

      def send_complete_notification(sources, export_dir)
        Gio::Notification.new(_("Compression Complete")).tap do |notification|
          notification.category = "transfer.complete"
          notification.body = notification_body(sources)
          notification.set_default_action_and_target(
            "app.focus-window",
            GLib::Variant.new(id, "i"),
          )
          notification.add_button_with_target(
            _("Open Export Directory"),
            "app.open-dir",
            GLib::Variant.new(export_dir, "s"),
          )

          @application.send_notification(complete_notification_id, notification)
        end
      end

      def notification_body(sources)
        if sources.length == 1
          interpolate(_("“{}” processed"), sources.first.display_name)
        else
          interpolate(
            ngettext("{} file processed", "{} files processed", sources.length),
            sources.length,
          )
        end
      end

      # --- Compression ------------------------------------------------------

      # Compresses every queued video into the chosen directory, one after
      # another. Runs on a background thread: every UI call below goes through
      # Shared.update_ui with the daemon flag set.
      def bulk_compress(destination_dir)
        set_controls_lock(true, true)
        show_cancel_button(true, true)
        @compressing = true

        run = {
          codec:           video_codec,
          destination_dir: destination_dir,
          extra_quality:   extra_quality,
          fps_mode:        fps_mode,
          sources:         sources_list_box.all,
          target_size:     target_size,
          tolerance:       tolerance,
          use_ha:          @settings["use-gpu-encoding"],
        }

        # Compressing a queue can take hours, and a suspend mid-encode loses
        # the attempt, so sleep and logout are held off for the duration.
        cookie = @application.inhibit(
          self,
          Gtk::ApplicationInhibitFlags::SUSPEND | Gtk::ApplicationInhibitFlags::LOGOUT,
          _("Videos are being compressed"),
        )

        compress_queue(run)

        GLib::Idle.add do
          finish_compression(run, cookie)
          GLib::Source::REMOVE
        end
      end

      def compress_queue(run)
        displayed_dest = displayed_destination(run.fetch(:destination_dir))

        run.fetch(:sources).each_with_index do |video, index|
          set_compressing_title(index, displayed_dest)

          unless video.state == SourceState::COMPLETE
            if compress_one(video, run) == :cancelled
              break
            end
          end
        end
      end

      # Returns :cancelled when the run was stopped part-way through this
      # video, which is what ends the queue early.
      def compress_one(video, run)
        @currently_processed = video.display_name
        progress_box = CurrentAttemptBox.new
        video.initiate_popover_box(progress_box, true)
        video.set_state(SourceState::COMPRESSING, true)

        output_path = unique_path(export_path(video, run.fetch(:destination_dir)))

        result = Utils.compress(
          file_input:       video.video_path,
          input_mime_type:  video.mime_type.to_s,
          file_output:      output_path,
          target_size_mib:  run.fetch(:target_size),
          framerate_option: run.fetch(:fps_mode),
          extra_quality:    run.fetch(:extra_quality),
          codec:            run.fetch(:codec),
          use_ha:           run.fetch(:use_ha),
          tolerance:        run.fetch(:tolerance),
          log_path:         log_path(run.fetch(:destination_dir)),
          cancel_event:     -> { !@compressing },
          on_new_attempt:   attempt_callback(progress_box),
          on_attempt_fail:  fail_callback(video),
          &progress_callback(video, progress_box, run.fetch(:codec))
        )

        handle_compression_result(video, output_path, result)
      end

      def handle_compression_result(video, output_path, result)
        if result.is_a?(String)
          video.set_error(result, true)
          Shared.update_ui(true) { toast_overlay.add_toast(error_toast(video)) }
          trash_video(output_path)
          :failed
        elsif @compressing
          video.set_complete(
            output_path,
            (result / 1024.0 / 1024.0).round(1),
            true,
          )
          :complete
        else
          # Stopped part-way: the half-encoded file goes to the wastebasket
          # rather than cluttering the export folder, and the row goes back to
          # showing its preview.
          video.set_preview(-> { target_size }, -> { fps_mode }, true)
          trash_video(output_path)
          :cancelled
        end
      end

      # VP9's software first pass reports no progress at all, so its 0.0
      # fraction drives a spinner and a pulsing bar instead of a percentage.
      def progress_callback(video, progress_box, codec)
        lambda do |fraction, seconds_left|
          if fraction == 0.0 && codec == VideoCodec::VP9
            progress_box.set_progress_text(_("Analyzing…"), true)
            video.enable_spinner(true, true)
            progress_box.pulse_progress(true)
          else
            video.enable_spinner(false, true)
            progress_box.set_progress(fraction, seconds_left, true)
            video.set_fraction(fraction, true)
          end
        end
      end

      def attempt_callback(progress_box)
        lambda do |attempt, bitrate, hq_audio, height, fps|
          progress_box.set_attempt_details(
            attempt_no:  attempt,
            vid_bitrate: bitrate,
            is_hq_audio: hq_audio,
            vid_height:  height,
            vid_fps:     fps,
            daemon:      true,
          )
        end
      end

      def fail_callback(video)
        lambda do |attempt, bitrate, hq_audio, height, fps, after_bytes, target_bytes|
          video.add_attempt_fail(
            attempt_no:            attempt,
            vid_bitrate:           bitrate,
            is_hq_audio:           hq_audio,
            vid_height:            height,
            vid_fps:               fps,
            compressed_size_bytes: after_bytes,
            target_size_bytes:     target_bytes,
            daemon:                true,
          )
        end
      end

      def finish_compression(run, cookie)
        set_controls_lock(false, false)
        show_cancel_button(false, false)
        refresh_can_export(false)

        unless cookie.zero?
          @application.uninhibit(cookie)
        end

        set_queued_title(false)

        if @compressing
          toast_overlay.add_toast(Adwaita::Toast.new(_("Compression complete")))
          send_complete_notification(
            run.fetch(:sources),
            run.fetch(:destination_dir),
          )
        end

        @compressing = false
      end

      def error_toast(video)
        Adwaita::Toast.new(
          interpolate(_("Error compressing “{}”"), video.display_name),
        ).tap do |toast|
          toast.use_markup = false
          toast.button_label = _("View _Details")
          toast.signal_connect("button-clicked") do
            error_dialog(video.display_name, video.error_details)
          end
        end
      end

      # The export path: the input's name, the custom or default suffix, and
      # the .mp4 extension pass 2 always writes.
      def export_path(video, destination_dir)
        suffix = @settings["custom-export-suffix"]
        if suffix.to_s.empty?
          suffix = @application.default_suffix
        end

        File.join(destination_dir, File.basename(video.video_path)).then do |merged|
          "#{merged.delete_suffix(File.extname(merged))}#{suffix}.mp4"
        end
      end

      # Never overwrites: an existing name gains a `-1`, `-2` … counter.
      def unique_path(file_path)
        extension = File.extname(file_path)
        root = file_path.delete_suffix(extension)
        final_path = file_path
        counter = 0

        while File.exist?(final_path)
          counter += 1
          final_path = "#{root}-#{counter}#{extension}"
        end

        final_path
      end

      # The two-pass log is per window, and lands in the export directory only
      # when there is no temp directory to put it in.
      def log_path(destination_dir)
        "constrict2pass-#{id}".then do |filename|
          Shared.tmp_dir.then do |tmp_dir|
            if tmp_dir
              File.join(tmp_dir, filename)
            else
              File.join(destination_dir, filename)
            end
          end
        end
      end

      def trash_video(output_path)
        Gio::File.new_for_path(output_path).trash
      rescue GLib::Error
        nil
      end

      # The directory as it is worth showing the user: the host path under
      # Flatpak, with the home directory shortened to `~`.
      def displayed_destination(destination_dir)
        host_path(destination_dir).then do |path|
          GLib.home_dir.then do |home|
            if path.start_with?(home)
              path.sub(home, "~")
            else
              path
            end
          end
        end
      end

      # --- Staging ----------------------------------------------------------

      # Flattens a file list, walking directories in name order so a dropped
      # folder queues its videos the way the file manager shows them.
      def flatten_files(file_list)
        file_list.flat_map do |file|
          if file.query_file_type(Gio::FileQueryInfoFlags::NONE) == Gio::FileType::DIRECTORY
            flatten_files(children_of(file))
          else
            [file]
          end
        end
      end

      def children_of(directory)
        enumerator = directory.enumerate_children(
          "standard::name",
          Gio::FileQueryInfoFlags::NONE,
        )
        children = []

        while (info = enumerator.next_file)
          children.push(enumerator.get_child(info))
        end

        children.sort_by(&:basename)
      rescue GLib::Error
        []
      end

      def stage_video(file, existing_paths, unsupported_mimes)
        if file.query_exists
          file_info(file).then do |info|
            if info
              staged_row_for(
                file,
                info,
                existing_paths,
                unsupported_mimes,
              )
            end
          end
        end
      end

      def staged_row_for(file, info, existing_paths, unsupported_mimes)
        mime_type = info.content_type

        if mime_type.nil? || existing_paths.include?(host_path(file.path))
          nil
        elsif video_mime?(mime_type)
          build_source_row(file, info, mime_type)
        else
          unsupported_mimes.push(mime_type)
          nil
        end
      end

      def video_mime?(mime_type)
        mime_type.start_with?(VIDEO_MIME_PREFIX) || mime_type == GIF_MIME_TYPE
      end

      def build_source_row(file, info, mime_type)
        SourcesRow.new(
          video_path:         file.path,
          display_name:       info.display_name || file.basename,
          mime_type:          mime_type,
          file_hash:          file.hash,
          target_size_getter: -> { target_size },
          fps_mode_getter:    -> { fps_mode },
          error_action:       ->(name, details) { error_dialog(name, details) },
          warning_action:     ->(is_error, daemon) { set_warning_state(is_error, daemon) },
          remove_action:      ->(row) { remove_row(row) },
        )
      end

      def file_info(file)
        file.query_info(
          "standard::display-name,standard::content-type",
          Gio::FileQueryInfoFlags::NONE,
        )
      rescue GLib::Error
        nil
      end

      # Under Flatpak the path the app sees is a portal path that differs
      # between runs, so the host path recorded in the file's xattrs is what
      # two queued copies of the same video are compared by.
      def host_path(path)
        Gio::File.new_for_path(path).then do |file|
          file.query_info(
            "xattr::document-portal.host-path",
            Gio::FileQueryInfoFlags::NONE,
          ).get_attribute_string("xattr::document-portal.host-path") || path
        end
      rescue GLib::Error
        path
      end
  end
end
