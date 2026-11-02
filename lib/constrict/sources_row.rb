# frozen_string_literal: true

require "adwaita"

require_relative "attempt_fail_box"
require_relative "constrict_utils"
require_relative "enums"
require_relative "i18n"
require_relative "progress_pie"
require_relative "progress_popover_box"
require_relative "shared"

module Constrict
  # Ported from upstream's src/sources_row.blp and src/sources_row.py.
  #
  # One video queued for compression. The row carries the video's path and the
  # properties probed off it, and a state (see Constrict::SourceState) that
  # decides which of its five suffix buttons is showing: the progress pie while
  # compressing, a tick when done, an error button when ffmpeg failed, a broken
  # -video button when the file cannot be read, and a warning or error button
  # when the target size does not suit the file.
  #
  # Upstream's acknowledgement stands: the drag-and-drop reordering is modelled
  # on GNOME Settings' input rows and GNOME Music's song widget.
  class SourcesRow < Adwaita::ActionRow
    include I18n

    type_register

    # Below this bitrate a compression is near-certain to fail after wasting
    # several attempts, so the row refuses the target up front. The threshold
    # is deliberately higher than the backend's own 5 kbps floor.
    MIN_VIABLE_BITRATE = 11_000

    attr_reader :video_path, :display_name, :mime_type, :state, :error_details
    attr_reader :compressed_path, :popover_box

    def initialize(
      video_path:,
      display_name:,
      mime_type: nil,
      file_hash: nil,
      target_size_getter: nil,
      fps_mode_getter: nil,
      error_action: nil,
      warning_action: nil,
      remove_action: nil
    )
      super()
      @video_path = video_path
      @display_name = display_name
      @mime_type = mime_type
      @state = SourceState::PENDING
      @error_details = ""
      @error_action = error_action
      @warning_action = warning_action
      @remove_action = remove_action
      @properties = {}
      @drag_position = [0, 0]
      build
      start_background_work(file_hash, target_size_getter, fps_mode_getter)
    end

    def build
      tap do |row|
        row.title = @display_name
        row.title_lines = 2
        row.subtitle_lines = 1
        row.use_markup = false
        row.selectable = false
        row.insert_action_group("row", action_group)

        row.add_prefix(thumbnail)
        row.add_prefix(drag_handle_revealer)
        row.add_suffix(error_icon)
        row.add_suffix(video_broken_button)
        row.add_suffix(incompatible_button)
        row.add_suffix(progress_button)
        row.add_suffix(complete_button)
        row.add_suffix(menu_button)

        row.add_controller(drag_source)
        row.add_controller(drop_target)

        drag_handle_revealer.tap { |revealer| revealer.child = drag_handle }

        video_broken_button.tap do |button|
          button.popover = broken_popover
          broken_popover.tap { |popover| popover.child = broken_label }
        end

        incompatible_button.tap do |button|
          button.popover = incompatible_popover
          incompatible_popover.tap { |popover| popover.child = incompatible_label }
        end

        progress_button.tap do |button|
          button.child = progress_box
          button.popover = progress_popover

          progress_box.tap do |box|
            box.append(progress_pie)
            box.append(progress_spinner)
          end

          progress_popover.tap { |popover| popover.child = popover_scrolled_window }
        end

        complete_button.tap do |button|
          button.popover = complete_popover

          complete_popover.tap { |popover| popover.child = complete_box }

          complete_box.tap do |box|
            box.append(complete_label)
            box.append(find_file_button)
          end
        end

        connect_popover_announcements
        connect_drag_handlers
      end
    end

    # --- Widgets ------------------------------------------------------------

    def thumbnail
      @thumbnail ||= Gtk::Image.new.tap do |image|
        image.icon_name = "image-loading"
        image.icon_size = :large
        image.valign = :center
        image.add_css_class("icon-dropshadow")
      end
    end

    def drag_handle_revealer
      @drag_handle_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_right
        revealer.reveal_child = true
      end
    end

    def drag_handle
      @drag_handle ||= Gtk::Image.new.tap do |image|
        image.icon_name = "list-drag-handle-symbolic"
        image.add_css_class("drag-handle")
      end
    end

    def error_icon
      @error_icon ||= Gtk::Button.new.tap do |button|
        button.icon_name = "error-outline-symbolic"
        button.tooltip_text = _("View Error Details")
        button.valign = :center
        button.visible = false
        button.action_name = "row.on-error"
        button.add_css_class("error")
        button.add_css_class("flat")
      end
    end

    def video_broken_button
      @video_broken_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "broken-video-symbolic"
        button.tooltip_text = _("View Error Details")
        button.valign = :center
        button.visible = false
        button.add_css_class("error")
        button.add_css_class("flat")
      end
    end

    def broken_popover = @broken_popover ||= Gtk::Popover.new

    def broken_label
      @broken_label ||= popover_label(_("Cannot load video. It may be missing or corrupted."))
    end

    # Carries both the blocking "target size is too low" error and the
    # non-blocking "already small enough" warning; set_incompatible and
    # set_warning restyle it.
    def incompatible_button
      @incompatible_button ||= Gtk::MenuButton.new.tap do |button|
        button.valign = :center
        button.visible = false
      end
    end

    def incompatible_popover = @incompatible_popover ||= Gtk::Popover.new
    def incompatible_label = @incompatible_label ||= popover_label("")

    def progress_button
      @progress_button ||= Gtk::MenuButton.new.tap do |button|
        button.visible = false
        button.tooltip_text = _("View Compression Progress")
        button.valign = :center
        button.add_css_class("flat")
      end
    end

    def progress_box = @progress_box ||= Gtk::Box.new(:horizontal, 0)

    def progress_pie
      @progress_pie ||= ProgressPie.new.tap do |pie|
        pie.width_request = 16
        pie.height_request = 16
      end
    end

    # Shown in place of the pie while a pass reports no progress at all, which
    # is what VP9's software first pass does.
    def progress_spinner
      @progress_spinner ||= Adwaita::Spinner.new.tap do |spinner|
        spinner.visible = false
        spinner.width_request = 16
        spinner.height_request = 16
      end
    end

    def progress_popover = @progress_popover ||= Gtk::Popover.new

    def popover_scrolled_window
      @popover_scrolled_window ||= Gtk::ScrolledWindow.new.tap do |window|
        window.propagate_natural_height = true
        window.propagate_natural_width = true
      end
    end

    def complete_button
      @complete_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "check-plain-symbolic"
        button.tooltip_text = _("More Details")
        button.valign = :center
        button.visible = false
        button.add_css_class("success")
        button.add_css_class("flat")
      end
    end

    def complete_popover = @complete_popover ||= Gtk::Popover.new

    def complete_box
      @complete_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.margin_start = 6
        box.margin_end = 6
        box.margin_top = 6
        box.margin_bottom = 6
      end
    end

    def complete_label
      @complete_label ||= Gtk::Label.new.tap do |label|
        label.wrap = true
        label.max_width_chars = 30
      end
    end

    def find_file_button
      @find_file_button ||= Gtk::Button.new.tap do |button|
        button.margin_top = 9
        button.label = _("Show File Location")
        button.action_name = "row.find-compressed-file"
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "view-more-symbolic"
        button.tooltip_text = _("View More")
        button.valign = :center
        button.menu_model = row_actions
        button.add_css_class("flat")
      end
    end

    def row_actions
      @row_actions ||= Gio::Menu.new.tap do |menu|
        menu.append_section(
          nil,
          Gio::Menu.new.tap do |section|
            section.append(_("Move _Up"), "row.move-up")
            section.append(_("Move _Down"), "row.move-down")
          end,
        )
        menu.append_section(
          nil,
          Gio::Menu.new.tap { |section| section.append(_("_Remove"), "row.remove") },
        )
      end
    end

    def drag_source
      @drag_source ||= Gtk::DragSource.new.tap do |source|
        source.actions = :move
        source.propagation_phase = :none
      end
    end

    def drop_target
      @drop_target ||= Gtk::DropTarget.new(self.class.gtype, :move).tap do |target|
        target.preload = true
      end
    end

    # Upstream installs the five row actions on the widget class with
    # gtk_widget_class_install_action, which the Ruby bindings do not expose;
    # an action group under the same "row" prefix keeps every `row.*` name the
    # menu and the suffix buttons point at.
    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        {
          "move-up"              => -> { move_up },
          "move-down"            => -> { move_down },
          "on-error"             => -> { @error_action&.call(@display_name, @error_details) },
          "find-compressed-file" => -> { find_compressed_file },
          "remove"               => -> { @remove_action&.call(self) },
        }.each do |name, handler|
          group.add_action(
            Gio::SimpleAction.new(name).tap do |action|
              action.signal_connect("activate") { handler.call }
            end,
          )
        end
      end
    end

    # --- State --------------------------------------------------------------

    # Sets the row's state and shows the one suffix button that belongs to it.
    def set_state(state, daemon)
      unless state == @state
        broken_or_incompatible = [
          SourceState::BROKEN,
          SourceState::INCOMPATIBLE,
        ].include?(state)

        if broken_or_incompatible
          @warning_action&.call(true, daemon)
        end

        Shared.update_ui(daemon) do
          progress_button.visible = state == SourceState::COMPRESSING
          complete_button.visible = state == SourceState::COMPLETE
          error_icon.visible = state == SourceState::ERROR
          video_broken_button.visible = state == SourceState::BROKEN
          incompatible_button.visible =
            [SourceState::INCOMPATIBLE, SourceState::WARN].include?(state)
        end

        @state = state
      end
    end

    # A problem with the target size that blocks exporting.
    def set_incompatible(message, daemon)
      Shared.update_ui(daemon) do
        incompatible_button.icon_name = "exclamation-mark-symbolic"
        incompatible_button.css_classes = ["flat", "error"]
        incompatible_button.tooltip_text = _("View Error Details")
        incompatible_label.label = message
      end

      set_state(SourceState::INCOMPATIBLE, daemon)
    end

    # A problem with the target size that does not block exporting.
    def set_warning(message, daemon)
      Shared.update_ui(daemon) do
        incompatible_button.icon_name = "warning-outline-symbolic"
        incompatible_button.css_classes = ["flat", "warning"]
        incompatible_button.tooltip_text = _("More Information")
        incompatible_label.label = message
      end

      set_state(SourceState::WARN, daemon)
    end

    # Puts the row into its error state, holding the ffmpeg output the error
    # dialog will show.
    def set_error(error_details, daemon)
      @error_details = error_details
      set_state(SourceState::ERROR, daemon)
    end

    def set_complete(compressed_video_path, compressed_size_mb, daemon)
      Shared.update_ui(daemon) do
        complete_label.label = interpolate(
          _("Video compressed to {size}\u202F{unit}."),
          size: compressed_size_mb,
          unit: _("MiB"),
        )
        progress_popover.popdown
      end

      @compressed_path = compressed_video_path
      set_state(SourceState::COMPLETE, daemon)
    end

    # Decides between pending, warning and incompatible for a freshly computed
    # video bitrate. A broken row stays broken: nothing about the target size
    # can fix a file that cannot be read.
    def refresh_state(video_bitrate, target_size, daemon)
      unless @state == SourceState::BROKEN
        if size < target_size * 1024 * 1024
          set_warning(already_small_enough_message(target_size), daemon)
        elsif video_bitrate < MIN_VIABLE_BITRATE
          set_incompatible(
            interpolate(
              _("Target size ({size}\u202F{unit}) is too low for this file."),
              size: target_size,
              unit: _("MiB"),
            ),
            daemon,
          )
        else
          set_state(SourceState::PENDING, daemon)
        end
      end
    end

    # Writes the row's subtitle: the source resolution and framerate, an
    # arrow, and what the compressed video will be. Probing the video is how a
    # broken file is discovered, so this is also where BROKEN is set.
    def set_preview(target_size_getter, fps_mode_getter, daemon)
      unless @state == SourceState::BROKEN
        begin
          probe_properties
        rescue ProbeError
          set_state(SourceState::BROKEN, daemon)
        end

        unless @state == SourceState::BROKEN
          write_preview(target_size_getter.call, fps_mode_getter.call, daemon)
        end
      end
    end

    # --- Compression progress ----------------------------------------------

    # Puts a fresh progress popover body in place for a new compression run.
    def initiate_popover_box(top_widget, daemon)
      @popover_box = ProgressPopoverBox.new(top_widget)

      Shared.update_ui(daemon) do
        popover_scrolled_window.child = @popover_box
      end
    end

    def add_attempt_fail(
      attempt_no:,
      vid_bitrate:,
      is_hq_audio:,
      vid_height:,
      vid_fps:,
      compressed_size_bytes:,
      target_size_bytes:,
      daemon:
    )
      if @popover_box
        @popover_box.add_fail_widget(
          AttemptFailBox.new(
            attempt_no:            attempt_no,
            vid_bitrate:           vid_bitrate,
            is_hq_audio:           is_hq_audio,
            vid_height:            vid_height,
            vid_fps:               vid_fps,
            compressed_size_bytes: compressed_size_bytes,
            target_size_bytes:     target_size_bytes,
          ),
          daemon,
        )
      end
    end

    # Swaps the progress pie for a spinner, for a pass that reports no
    # progress to show.
    def enable_spinner(enable, daemon)
      Shared.update_ui(daemon) do
        progress_pie.visible = !enable
        progress_spinner.visible = enable
      end
    end

    def set_fraction(fraction, daemon)
      Shared.update_ui(daemon) { progress_pie.fraction = fraction }
    end

    # --- Reordering ---------------------------------------------------------

    def set_draggable(can_drag)
      phase = :none
      if can_drag
        phase = :capture
      end

      drag_source.propagation_phase = phase
    end

    def show_drag_handle(shown)
      drag_handle_revealer.reveal_child = shown
    end

    def set_action_enabled(name, enabled)
      action_group.lookup_action(name).enabled = enabled
    end

    # --- Video properties ---------------------------------------------------

    # Each property is probed once and cached on the row, as upstream's
    # per-property getters do.
    def resolution = probed(:resolution) { Utils.resolution(@video_path) }
    def fps = probed(:fps) { Utils.framerate(@video_path) }
    def duration = probed(:duration) { Utils.duration(@video_path) }
    def audio_bitrate = probed(:audio_bitrate) { Utils.audio_bitrate(@video_path) }
    def size = probed(:size) { File.size(@video_path) }

    def audio_channel_count
      probed(:audio_channel_count) { Utils.audio_channel_count(@video_path) }
    end

    private

      def probed(key)
        unless @properties.key?(key)
          @properties[key] = yield
        end

        @properties[key]
      end

      def probe_properties
        resolution
        fps
        duration
        audio_bitrate
        audio_channel_count
        size
      end

      def popover_label(text)
        Gtk::Label.new(text).tap do |label|
          label.margin_start = 6
          label.margin_end = 6
          label.margin_top = 6
          label.margin_bottom = 6
          label.wrap = true
          label.max_width_chars = 30
          label.valign = :center
          label.halign = :center
        end
      end

      def already_small_enough_message(target_size)
        (size / 1024.0 / 1024.0).round(1).then do |size_mb|
          interpolate(
            _(
              "Video file size ({original_size}\u202F{unit_original}) " \
              "already meets the target size " \
              "({target_size}\u202F{unit_target}).",
            ),
            original_size: size_mb,
            unit_original: _("MiB"),
            target_size:   target_size,
            unit_target:   _("MiB"),
          )
        end
      end

      # The thumbnail and the first preview both shell out to ffprobe, so both
      # run off the main loop and update the row through Shared.update_ui.
      def start_background_work(file_hash, target_size_getter, fps_mode_getter)
        if file_hash
          Thread.new { set_thumbnail(file_hash, true) }
        end

        if target_size_getter && fps_mode_getter
          Thread.new { set_preview(target_size_getter, fps_mode_getter, true) }
        end
      end

      def write_preview(target_size_mib, fps_mode, daemon)
        width, height = resolution
        original_size_mib = size / 1024.0 / 1024.0
        # A target larger than the file itself means a plain transcode at the
        # file's own size rather than a compression towards a smaller one.
        basic_transcode = target_size_mib > original_size_mib
        target_size_cap_mib = target_size_mib
        if basic_transcode
          target_size_cap_mib = original_size_mib
        end

        assumed_fps = fps
        if fps == -1
          assumed_fps = 60
        end

        settings = Utils.encode_settings(
          target_size_mib: target_size_cap_mib,
          fps_mode:        fps_mode,
          width:           width,
          height:          height,
          fps:             assumed_fps,
          duration:        duration,
          audio_bitrate:   audio_bitrate,
          basic_transcode: basic_transcode,
        )

        video_bitrate, _audio_bitrate, target_pixels, target_fps = settings

        refresh_state(video_bitrate, target_size_mib, daemon)

        if @state == SourceState::INCOMPATIBLE
          Shared.update_ui(daemon) { self.subtitle = "" }
        else
          Shared.update_ui(daemon) do
            self.subtitle = preview_subtitle(target_pixels, target_fps)
          end
        end
      end

      def preview_subtitle(target_pixels, target_fps)
        src_fps = "?"
        unless fps == -1
          src_fps = fps.round.to_s
        end

        src_label = "#{resolution.min}p@#{src_fps}"
        dest_label = "#{target_pixels}p@#{target_fps.round}"

        if direction == Gtk::TextDirection::RTL
          "#{dest_label} ← #{src_label}"
        else
          "#{src_label} → #{dest_label}"
        end
      end

      # Runs the system video thumbnailer into the temp directory, named by the
      # file's hash, and shows the result. Any step that fails falls back to a
      # generic icon.
      def set_thumbnail(file_hash, daemon)
        generic_icon = "video-x-generic"
        if @mime_type == "image/gif"
          generic_icon = "image-x-generic"
        end

        thumbnail_path(file_hash).then do |path|
          if path && File.exist?(path)
            Shared.update_ui(daemon) { thumbnail.file = path }
          else
            Shared.update_ui(daemon) { thumbnail.icon_name = generic_icon }
          end
        end
      end

      def thumbnail_path(file_hash)
        thumbnailer = GLib.find_program_in_path("gst-video-thumbnailer")

        Shared.tmp_dir.then do |tmp_dir|
          if thumbnailer && tmp_dir
            File.join(tmp_dir, "#{file_hash}.jpg").then do |path|
              system(

                thumbnailer,
                "-p",

                @video_path,
                "-s",

                "128",
                "-o",

                path,
                out: File::NULL,
                err: File::NULL,

              )
              path
            end
          end
        end
      end

      def connect_popover_announcements
        {
          broken_popover       => -> { broken_label.text },
          incompatible_popover => -> { incompatible_label.text },
          complete_popover     => -> { complete_label.text },
          progress_popover     => -> { @popover_box&.message },
        }.each do |popover, message|
          popover.signal_connect("show") do
            message.call.then do |text|
              if text
                announce(text, Gtk::AccessibleAnnouncementPriority::MEDIUM)
              end
            end
          end
        end
      end

      def connect_drag_handlers
        drag_source.tap do |source|
          source.signal_connect("prepare") { |_, x, y| on_drag_prepare(x, y) }
          source.signal_connect("drag-begin") { |_, drag| on_drag_begin(drag) }
        end

        drop_target.tap do |target|
          target.signal_connect("motion") { |_, _x, _y| on_motion }
          target.signal_connect("drop") { |_, value, _x, _y| on_drop(value) }
        end
      end

      def on_drag_prepare(pointer_x, pointer_y)
        @drag_position = [pointer_x, pointer_y]
        Gdk::ContentProvider.new(GLib::Value.new(self.class.gtype, self))
      end

      # The dragged row follows the cursor as a one-row list box, highlighted
      # the way the real list box would highlight it.
      def on_drag_begin(drag)
        Gtk::ListBox.new.tap do |drag_widget|
          drag_widget.set_size_request(width, -1)

          drag_row(drag_widget)

          Gtk::DragIcon.get_for_drag(drag).child = drag_widget
          drag.set_hotspot(@drag_position[0], @drag_position[1])
        end
      end

      def drag_row(drag_widget)
        SourcesRow.new(
          video_path:   @video_path,
          display_name: @display_name,
        ).tap do |row|
          row.subtitle = subtitle.to_s
          row.set_state(@state, false)

          if @state == SourceState::WARN
            row.set_warning("", false)
          end

          copy_thumbnail_to(row)

          drag_widget.append(row)
          drag_widget.drag_highlight_row(row)
        end
      end

      def copy_thumbnail_to(row)
        if thumbnail.storage_type == Gtk::ImageType::ICON_NAME
          row.thumbnail.icon_name = thumbnail.icon_name
        elsif thumbnail.storage_type == Gtk::ImageType::PAINTABLE
          row.thumbnail.paintable = thumbnail.paintable
        end
      end

      # Rows may only be reordered within one list box: a drag from another
      # Constrict window is refused rather than moving the row between queues.
      def on_motion
        if drop_target.value.respond_to?(:parent) && drop_target.value.parent == parent
          Gdk::DragAction::MOVE
        else
          0
        end
      end

      def on_drop(source_row)
        @drag_position = [0, 0]

        if source_row.index == index || source_row.parent != parent
          false
        else
          parent.move(source_row, self)
          true
        end
      end

      def move_up
        parent.then do |list_box|
          list_box.get_row_at_index(index - 1).then do |previous_row|
            if previous_row
              list_box.move(self, previous_row)
            end
          end
        end
      end

      def move_down
        parent.then do |list_box|
          list_box.get_row_at_index(index + 1).then do |next_row|
            if next_row && next_row != list_box.add_videos_button
              list_box.move(self, next_row)
            end
          end
        end
      end

      # Opens the compressed video's folder in the file manager. Under Flatpak
      # the path the app sees is a portal path, so the host path recorded in
      # the file's xattrs is preferred when there is one.
      def find_compressed_file
        complete_popover.popdown

        Gio::File.new_for_path(@compressed_path).then do |file|
          host_path(file).then do |path|
            launcher_file = file
            if path
              launcher_file = Gio::File.new_for_path(path)
            end

            Gtk::FileLauncher.new(launcher_file).open_containing_folder
          end
        end
      end

      def host_path(file)
        file.query_info(
          "xattr::document-portal.host-path",
          Gio::FileQueryInfoFlags::NONE,
        ).get_attribute_string("xattr::document-portal.host-path")
      rescue GLib::Error
        nil
      end
  end
end
