# frozen_string_literal: true

# Drives the whole app headlessly: builds the window, stages real and
# unsupported files, exercises every dialog (preferences, error, shortcuts,
# about, cancel-confirmation), the primary menu, the sidebar breakpoint, the
# sources list box's locking and reordering, a source row's own menu and
# suffix buttons, the application- and window-level actions and
# accelerators, and the non-widget halves (Settings, Enums, Style, the CLI
# option parser, i18n) that the widgets above lean on.
#
# Why this file exists: a GTK app that loads is not a GTK app that works.
# `ruby -c` and a clean `require` pass on code whose dialogs never open and
# whose buttons are wired to nothing; only running it and looking at what
# happened proves anything. The previous drive script here
# (test/drive_window.rb) printed a handful of values and never asserted or
# screenshotted anything, so a regression in any of it would have printed
# something plausible-looking and still exited 0.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/drive_constrict.rb
#
# Out of scope, and why: this machine's dev shell ships no `ffprobe`,
# `ffmpeg`, `gst-video-thumbnailer` or `vainfo` (the compression backend's
# whole toolchain), so every staged video in this run is probed, fails, and
# goes BROKEN — which is itself exercised below as the failure path real
# users hit on a corrupt file, but the success path (an actual two-pass
# compress) cannot be driven here. `Gtk::FileDialog` is also not driven by
# clicking, per the companion skill: it is async, backed by a portal this
# display has none of, and raises on cancel. The code behind each of its call
# sites (`stage_videos`, the export path builder) is driven directly instead.

require "fileutils"
require "tmpdir"

# A scratch config directory, so a run never reads or writes the real one.
ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir("constrict-drive")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "constrict"
require "constrict/cli"
require_relative "gtk_driver"

SHOTS = File.expand_path("../tmp/shots", __dir__)
FileUtils.rm_rf(SHOTS)

# Turns the main loop over for `ms` milliseconds and comes back.
#
# A step cannot sleep: a staged row's preview and thumbnail probe on their own
# Ruby threads and report back through GLib::Idle.add, which is only ever
# dispatched by the very loop a sleep would block. This iterates the default
# context without blocking until the deadline passes, which is what gives
# those threads' idle callbacks a chance to land before the next step reads
# their result.
# Puts `widget` in a throwaway toplevel so it is realised and laid out —
# needed before a screenshot of anything built outside the real window, since
# `Gtk::WidgetPaintable` only produces a render node for a widget that has
# actually been through layout. Returns the window so the caller can close it
# once the shot is taken.
def realize(widget)
  Gtk::Window.new.tap do |window|
    window.child = widget
    window.present
    pump(300)
  end
end

def pump(ms)
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) + (ms / 1000.0)).then do |deadline|
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      GLib::MainContext.default.iteration(false)
    end
  end
end

# A file whose content sniffs as a real video mime type, so `stage_videos`
# takes the video branch rather than the "unknown format" one. An empty file
# sniffs as `application/x-zerosize`; these are an ISO BMFF `ftyp` box, the
# magic bytes GIO (and file(1)) recognise as `video/mp4`.
def write_fake_mp4(path)
  File.open(path, "wb") do |file|
    file.write("\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom")
  end
end

# A real, 1x1 PNG (the shortest valid one: IHDR + a single-pixel IDAT +
# IEND), so glycin has actual image bytes to decode rather than a format it
# has to reject. Unlike the video thumbnailer, glycin ships in this dev
# shell, so this is the one thumbnailing step `DRIVE_DIR` can exercise for
# real rather than only through its failure path.
def write_fake_png(path)
  File.open(path, "wb") do |file|
    file.write(
      "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08" \
      "\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\xdacd\xf8\xff\xbf" \
      "\x1e\x00\x05\x84\x02\x7f\xc2[\x1e*\x00\x00\x00\x00IEND\xaeB`\x82",
    )
  end
end

DRIVE_DIR = Dir.mktmpdir("constrict-drive-files")
FAKE_MP4 = File.join(DRIVE_DIR, "holiday.mp4")
UNSUPPORTED_TXT = File.join(DRIVE_DIR, "notes.txt")
FAKE_PNG = File.join(DRIVE_DIR, "frame.png")
CORRUPT_PNG = File.join(DRIVE_DIR, "corrupt.png")
write_fake_mp4(FAKE_MP4)
File.write(UNSUPPORTED_TXT, "these are not video bytes")
write_fake_png(FAKE_PNG)
File.write(CORRUPT_PNG, "\x89PNG\r\n\x1a\nnot actually a png past the signature")

GtkDriver.drive(Constrict::Application.new(app_id: "org.rubygtkproject.ConstrictDrive"), shots: SHOTS) do |d, app|
  d.window { app.active_window }

  # --- 1. Application + Application (app.rb, window.rb): the window builds
  # empty -------------------------------------------------------------------

  d.step("the application activates and builds its first window") do
    d.check("there is exactly one window") { app.windows.length == 1 }
    app.active_window.then do |window|
      d.check("it is a ConstrictWindow") { window.is_a?(Constrict::ConstrictWindow) }
      d.check("it is the only toplevel") { Gtk::Window.list_toplevels.length == 1 }
      d.check("its title is Constrict") { window.title == "Constrict" }
      d.check("the status page is showing") do
        window.view_stack.visible_child_name == Constrict::ConstrictWindow::STATUS_PAGE
      end
      d.check("export starts disabled") { window.window_action("export").enabled? == false }
      # Not a fixed "disabled": this run's Xvfb display is narrower than the
      # breakpoint's own 750sp threshold, so on this machine the window
      # starts collapsed (and the action enabled) the same way a real,
      # narrow window would. What the breakpoint actually promises — that the
      # action is enabled exactly when the split view is collapsed, because
      # one `add_setter` call drives both — is what is checked instead.
      d.check("toggle-sidebar is enabled exactly when the split view is collapsed") do
        window.window_action("toggle-sidebar").enabled? == window.split_view.collapsed?
      end
      d.check("the open button points at win.open") { window.open_button.action_name == "win.open" }
      d.check("the status drag overlay wraps the status page") do
        window.status_drag_overlay.child.equal?(window.status_page)
      end
    end
    d.shot("01-empty")
  end

  d.step("every icon the window names resolves in the icon theme") do
    Gtk::IconTheme.get_for_display(Gdk::Display.default).then do |theme|
      [
        "video-encoder-symbolic", "sidebar-show-symbolic", "help-about-symbolic",
        "open-menu-symbolic", "list-add-symbolic", "list-drag-handle-symbolic",
        "error-outline-symbolic", "broken-video-symbolic", "check-plain-symbolic",
        "view-more-symbolic", "edit-copy-symbolic",
      ].each do |name|
        d.check("the icon theme resolves #{name}") { theme.has_icon?(name) }
      end
    end
  end

  # --- 2. The primary menu (window.rb's primary_menu) ----------------------

  d.step("the primary menu button carries upstream's menu, in two sections") do
    app.active_window.primary_menu.then do |menu|
      d.check("it is a Gio::Menu") { menu.is_a?(Gio::Menu) }
      d.check("it carries two sections") { menu.n_items == 2 }
    end
    app.active_window.primary_menu_button.then do |button|
      d.check("the header button is a MenuButton") { button.is_a?(Gtk::MenuButton) }
      d.check("its icon is the hamburger") { button.icon_name == "open-menu-symbolic" }
      d.check("it carries the same model") { button.menu_model.equal?(app.active_window.primary_menu) }
    end
  end

  # --- 3. stage_videos end to end: a real file, an unsupported one, and a
  # duplicate (window.rb) ----------------------------------------------------

  d.step("staging a video and an unsupported file") do
    app.active_window.stage_videos(
      [
        Gio::File.new_for_path(FAKE_MP4),
        Gio::File.new_for_path(UNSUPPORTED_TXT),
      ],
    )
  end

  d.step("the video queued and the text file did not") do
    app.active_window.then do |window|
      d.check("one row queued, not two") { window.sources_list_box.length == 1 }
      d.check("the queued row is the mp4") { window.sources_list_box.all.first.video_path == FAKE_MP4 }
      d.check("the view switched to the queue page") do
        window.view_stack.visible_child_name == Constrict::ConstrictWindow::QUEUE_PAGE
      end
      d.check("the title names the one queued file") { window.title == "“holiday.mp4” Queued" }
    end
  end

  # No ffprobe on this machine's PATH: probing fails exactly as it would on a
  # corrupted file, which is this run's only way to prove the BROKEN path
  # upstream calls the moment a source cannot be read at all.
  d.step("probing fails with no ffprobe, so the row goes BROKEN") do
    pump(1500)
    app.active_window.sources_list_box.all.first.then do |row|
      d.check("the row is BROKEN") { row.state == Constrict::SourceState::BROKEN }
      d.check("the broken button is the one showing") { row.video_broken_button.visible? }
      d.check("no other suffix button is showing") do
        !row.error_icon.visible? && !row.progress_button.visible? &&
          !row.complete_button.visible? && !row.incompatible_button.visible?
      end
    end
    d.check("the warning banner is revealed") { app.active_window.warning_banner.revealed? }
    d.check("export is disabled while a row is broken") do
      app.active_window.window_action("export").enabled? == false
    end
    d.shot("02-broken-row")
  end

  d.step("restaging the same file queues nothing new") do
    app.active_window.stage_videos([Gio::File.new_for_path(FAKE_MP4)])
    d.check("still one row") { app.active_window.sources_list_box.length == 1 }
  end

  d.step("removing the broken row empties the queue") do
    app.active_window.then do |window|
      window.remove_row(window.sources_list_box.all.first)
      d.check("no rows left") { window.sources_list_box.length.zero? }
      d.check("the status page is back") do
        window.view_stack.visible_child_name == Constrict::ConstrictWindow::STATUS_PAGE
      end
      d.check("the warning banner withdrew") { !window.warning_banner.revealed? }
    end
  end

  # --- 4. One row, built directly (no probing thread), driven widget by
  # widget: states, popovers, the suffix menu, drag source/drop target
  # (sources_row.rb, progress_pie.rb, progress_popover_box.rb,
  # current_attempt_box.rb, attempt_fail_box.rb) ----------------------------

  d.step("a row built directly moves through every suffix state") do
    Constrict::SourcesRow.new(video_path: FAKE_MP4, display_name: "demo.mp4").then do |row|
      d.check("it starts PENDING") { row.state == Constrict::SourceState::PENDING }
      d.check("every suffix button starts hidden") do
        [row.error_icon, row.video_broken_button, row.incompatible_button,
         row.progress_button, row.complete_button,].none?(&:visible?)
      end

      row.set_state(Constrict::SourceState::COMPRESSING, false)
      d.check("compressing shows the progress button") { row.progress_button.visible? }

      row.initiate_popover_box(Constrict::CurrentAttemptBox.new, false)
      row.popover_box.top_widget.set_attempt_details(
        attempt_no: 1, vid_bitrate: 800_000, is_hq_audio: true,
        vid_height: 720, vid_fps: 30.0, daemon: false,
      )
      row.popover_box.top_widget.set_progress(0.42, 90, false)
      row.set_fraction(0.42, false)
      d.check("the progress pie took the fraction") { row.progress_pie.fraction == 0.42 }
      d.check("the popover message names the attempt") { row.popover_box.message.include?("Attempt 1") }
      d.check("and the bitrate") { row.popover_box.message.include?("800") }

      row.add_attempt_fail(
        attempt_no: 1, vid_bitrate: 800_000, is_hq_audio: true, vid_height: 720,
        vid_fps: 30.0, compressed_size_bytes: 12 * 1024 * 1024,
        target_size_bytes: 10 * 1024 * 1024, daemon: false,
      )
      d.check("the fail widget was recorded") { row.popover_box.fail_widgets.length == 1 }
      d.check("it reads as too large") { row.popover_box.fail_widgets.first.failure_icon.icon_name == "arrow2-up-symbolic" }

      row.enable_spinner(true, false)
      d.check("the spinner swapped in for VP9's unreported pass") { row.progress_spinner.visible? }
      d.check("and the pie hid") { !row.progress_pie.visible? }
      row.enable_spinner(false, false)

      row.set_complete("/tmp/demo (compressed).mp4", 9.4, false)
      d.check("complete shows the complete button") { row.complete_button.visible? }
      d.check("and nothing else") { !row.progress_button.visible? }
      d.check("the complete label names the size") { row.complete_label.label.include?("9.4") }
      d.check("the compressed path was recorded") { row.compressed_path == "/tmp/demo (compressed).mp4" }

      row.set_error("ffmpeg: no such file", false)
      d.check("error shows the error icon") { row.error_icon.visible? }
      d.check("and nothing else") { !row.complete_button.visible? }
      d.check("the error details are held for the error dialog") do
        row.error_details == "ffmpeg: no such file"
      end

      row.set_incompatible("Target size (1 MiB) is too low for this file.", false)
      d.check("incompatible shows the incompatible button") { row.incompatible_button.visible? }
      d.check("styled as an error") { row.incompatible_button.has_css_class?("error") }
      d.check("the incompatible label carries the message") do
        row.incompatible_label.label == "Target size (1 MiB) is too low for this file."
      end

      row.set_warning("Video file size (1 MiB) already meets the target size (10 MiB).", false)
      d.check("warning reuses the incompatible button") { row.incompatible_button.visible? }
      d.check("but styled as a warning, not an error") { row.incompatible_button.has_css_class?("warning") }
      d.check("and the state is WARN, not INCOMPATIBLE") { row.state == Constrict::SourceState::WARN }

      row.menu_button.menu_model.then do |model|
        d.check("the row menu is a Gio::Menu") { model.is_a?(Gio::Menu) }
        d.check("it carries move-up, move-down and remove") { model.n_items == 2 }
      end

      row.set_draggable(true)
      d.check("the drag source captures when draggable") { row.drag_source.propagation_phase == :capture }
      row.set_draggable(false)
      d.check("and stops capturing when not") { row.drag_source.propagation_phase == :none }

      row.drag_source.signal_emit("prepare", 4.0, 5.0).then do |provider|
        d.check("prepare answers a content provider") { provider.is_a?(Gdk::ContentProvider) }
        d.check("offering the row itself") { provider.formats.to_s.include?("SourcesRow") }
      end
      d.check("the drop target accepts the same type") do
        row.drop_target.formats.to_s.include?("SourcesRow")
      end
      d.check("dragging moves rather than copies") { row.drag_source.actions == :move }

      row.show_drag_handle(false)
      d.check("the handle hides") { !row.drag_handle_revealer.reveal_child? }
      row.show_drag_handle(true)
      d.check("and comes back") { row.drag_handle_revealer.reveal_child? }

      row.set_action_enabled("remove", false)
      d.check("row actions can be disabled") { !row.action_group.lookup_action("remove").enabled? }
      row.set_action_enabled("remove", true)

      realize(row).then do |window|
        d.shot("03-row-states", row)
        window.close
      end
    end
  end

  # --- 4b. The real thumbnail decode path: glycin/libglycin-gtk4 turning an
  # actual image file into a paintable (sources_row.rb's texture_from_file,
  # the binding-gem code path this port's thumbnailer output flows through
  # once ffmpeg/gst-video-thumbnailer have written a frame to disk — neither
  # of which exists on this machine, so this step reaches `texture_from_file`
  # directly with a real PNG rather than through the thumbnailer shell-out
  # this dev shell cannot run) ------------------------------------------------

  d.step("glycin decodes a real image into a GdkTexture, live") do
    Constrict::SourcesRow.new(video_path: FAKE_MP4, display_name: "holiday.mp4").then do |row|
      texture = row.send(:texture_from_file, FAKE_PNG)
      d.check("a texture came back, not nil") { !texture.nil? }
      d.check("it is a real Gdk::Texture") { texture.is_a?(Gdk::Texture) }
      d.check("it decoded the 1x1 pixel's actual dimensions") do
        texture.width == 1 && texture.height == 1
      end

      # `set_thumbnail` -> `thumbnail_texture` shells out to
      # gst-video-thumbnailer before glycin ever sees a file, and this dev
      # shell has none (see the file's own "Out of scope" note), so that one
      # link is stubbed to hand `texture_from_file` the real PNG above —
      # exercising set_thumbnail's own UI-wiring half live, the same way the
      # file already drives `stage_videos` around ffprobe's absence.
      row.define_singleton_method(:thumbnail_texture) { |_file_hash| texture_from_file(FAKE_PNG) }
      row.send(:set_thumbnail, "whatever-hash", false)
      d.check("set_thumbnail wired a live-decoded texture onto the row's own image") do
        row.thumbnail.paintable.is_a?(Gdk::Texture) &&
          row.thumbnail.paintable.width == 1 && row.thumbnail.paintable.height == 1
      end
    end
  end

  d.step("a file glycin cannot decode falls back to the generic icon, not a crash") do
    Constrict::SourcesRow.new(video_path: FAKE_MP4, display_name: "holiday.mp4").then do |row|
      d.check("texture_from_file on bad bytes returns nil rather than raising") do
        row.send(:texture_from_file, CORRUPT_PNG).nil?
      end

      row.define_singleton_method(:thumbnail_texture) { |_file_hash| texture_from_file(CORRUPT_PNG) }
      row.send(:set_thumbnail, "whatever-hash", false)
      d.check("set_thumbnail fell back to the generic icon") { row.thumbnail.icon_name == "video-x-generic" }
    end
  end

  # --- 5. SourcesListBox: add, lock, reorder, remove (sources_list_box.rb) -

  d.step("the sources list box orders, locks and reorders real rows") do
    Constrict::SourcesListBox.new.then do |list|
      first = Constrict::SourcesRow.new(video_path: "/a.mp4", display_name: "a.mp4")
      second = Constrict::SourcesRow.new(video_path: "/b.mp4", display_name: "b.mp4")
      third = Constrict::SourcesRow.new(video_path: "/c.mp4", display_name: "c.mp4")

      list.add_sources([first, second, third])
      d.check("three rows, the add-videos row stays last") { list.length == 3 }
      d.check("in the order they were added") { list.all == [first, second, third] }
      d.check("the first row cannot move up") { first.action_group.lookup_action("move-up").enabled? == false }
      d.check("the last row cannot move down") do
        third.action_group.lookup_action("move-down").enabled? == false
      end
      d.check("the middle row can move either way") do
        second.action_group.lookup_action("move-up").enabled? &&
          second.action_group.lookup_action("move-down").enabled?
      end

      list.set_locked(true, false)
      d.check("locking disables every row's remove action") do
        [first, second, third].all? { |row| !row.action_group.lookup_action("remove").enabled? }
      end
      d.check("and hides every drag handle") do
        [first, second, third].none? { |row| row.drag_handle_revealer.reveal_child? }
      end
      list.set_locked(false, false)
      d.check("unlocking restores remove") { first.action_group.lookup_action("remove").enabled? }

      realize(list).then do |window|
        d.shot("04-list-box", list)
        window.close
      end

      list.move(third, first)
      d.check("moving the last row in front of the first reorders the list") do
        list.all == [third, first, second]
      end

      list.remove(first)
      d.check("removing drops to two rows") { list.length == 2 }
      d.check("and the remaining order is intact") { list.all == [third, second] }

      list.remove_all
      d.check("remove_all empties the queue") { list.length.zero? }
      d.check("any? reports false on an empty queue") { !list.any? }
    end
  end

  # --- 6. Dialogs: Preferences, Error, Shortcuts, About, Cancel confirmation
  # (preferences_dialog.rb, error_dialog.rb, shortcuts_dialog.rb,
  # application.rb) ----------------------------------------------------------

  d.step("the preferences dialog opens showing the settings it was built from") do
    app.active_window.then do |window|
      Constrict::PreferencesDialog.new(app.settings, app.default_suffix).then do |dialog|
        dialog.present(window)
        pump(300)
        d.check("the title is Preferences") { dialog.title == "Preferences" }
        d.check("the GPU row reflects the saved setting") do
          dialog.gpu_encoding_row.active? == app.settings["use-gpu-encoding"]
        end

        starting_gpu = dialog.gpu_encoding_row.active?
        dialog.gpu_encoding_row.active = !starting_gpu
        d.check("toggling the row writes straight through to settings") do
          app.settings["use-gpu-encoding"] == !starting_gpu
        end
        dialog.gpu_encoding_row.active = starting_gpu

        dialog.suffix_entry_row.text = " (tiny)"
        dialog.suffix_entry_row.signal_emit("apply")
        d.check("applying the suffix row writes the custom suffix") do
          app.settings["custom-export-suffix"] == " (tiny)"
        end
        app.settings["custom-export-suffix"] = ""

        pump(300)
        d.check("the dialog is mapped") { dialog.mapped? }
        d.shot("05-preferences")
        dialog.close
      end
    end
  end

  d.step("the error dialog shows the ffmpeg output and offers to copy it") do
    Constrict::ErrorDialog.new("demo.mp4", "ffmpeg: could not open input").then do |dialog|
      dialog.present(app.active_window)
      pump(300)
      d.check("the title is Compression Error") { dialog.title == "Compression Error" }
      d.check("the text view holds the error details verbatim") do
        dialog.text_view.buffer.text == "ffmpeg: could not open input"
      end
      d.check("the text view is read-only") { !dialog.text_view.editable? }
      d.check("the description names the file") { dialog.preference_page.description.include?("demo.mp4") }
      d.check("the copy action exists and is enabled") do
        dialog.action_group.lookup_action("copy-details").enabled?
      end
      d.check("activating it does not raise") do
        dialog.activate_action("dialog.copy-details", nil)
        true
      end
      pump(300)
      d.shot("06-error-dialog")
      dialog.close
    end
  end

  d.step("the shortcuts dialog's actions all resolve on the window or the app") do
    Constrict::ShortcutsDialog::SECTIONS.each do |_title, items|
      items.each do |_label, action_name|
        prefix, name = action_name.split(".", 2)
        d.check("#{action_name} is a real action") do
          if prefix == "win"
            app.active_window.window_actions.key?(name)
          else
            app.app_actions.key?(name)
          end
        end
      end
    end

    Constrict::ShortcutsDialog.new.then do |shortcuts|
      shortcuts.present(app.active_window)
      pump(300)
      d.check("the dialog is mapped") { shortcuts.dialog.mapped? }
      d.shot("07-shortcuts")
      shortcuts.dialog.close
    end
  end

  # `about_dialog` is a private memoized method on Application, so it is
  # reached with `send` — the same route `show_about` takes internally —
  # rather than reinventing a way to find it from outside once it is open.
  d.step("the about dialog carries the application's own credits") do
    app.send(:about_dialog).then do |dialog|
      dialog.present(app.active_window)
      pump(300)
      d.check("the application name is Constrict") { dialog.application_name == "Constrict" }
      d.check("its icon is the port's own") { dialog.application_icon == "video-encoder-symbolic" }
      d.check("the version is upstream's") { dialog.version == Constrict::Application::VERSION }
      d.check("the developer name matches") { dialog.developer_name == "Wartybix" }
      d.check("the copyright matches") { dialog.copyright == "© 2025 Wartybix" }
      d.check("the licence is GPL-3.0") { dialog.license_type == Gtk::License::GPL_3_0 }
      d.check("every developer upstream credits is listed") do
        dialog.developers == Constrict::Application::DEVELOPERS
      end
      d.check("the artist is credited") { dialog.artists == ["Jakub Steiner <jimmac@gmail.com>"] }
      d.check("the issue tracker is the port's own") do
        dialog.issue_url == "https://github.com/ruby-gtk-project/Constrict-rb/issues"
      end
      d.check("the dialog is mapped") { dialog.mapped? }
      d.shot("08-about")
      dialog.close
    end
  end

  # show_cancel_dialog is private to the window; `send` reaches it the same
  # way the "cancel" window action does internally, and — unlike going
  # through the action — hands back the AlertDialog itself to drive, since
  # neither the window nor the action keeps a reference to it anywhere
  # public.
  d.step("the cancel-confirmation dialog asks before throwing work away") do
    app.active_window.instance_variable_set(:@currently_processed, "holiday.mp4")
    app.active_window.send(:show_cancel_dialog, false).then do |dialog|
      pump(300)
      d.check("the dialog is mapped") { dialog.mapped? }
      d.check("it names the video that would be lost") { dialog.body.include?("holiday.mp4") }
      d.shot("09-cancel-confirm")

      app.active_window.instance_variable_set(:@compressing, true)
      dialog.signal_emit("response", "stop")
      pump(200)
      d.check("choosing stop ends the compression flag") do
        app.active_window.instance_variable_get(:@compressing) == false
      end
      # Emitting the signal by hand runs the "response" handler `.choose`
      # connected (which is what just resolved the check above) but not the
      # dialog's own default closing behaviour a real button click gets for
      # free, so the dialog is closed explicitly — the same step every other
      # dialog in this run takes once it has been read.
      dialog.close
    end
  end

  # --- 7. The breakpoint collapses and restores the sidebar (window.rb's
  # window_breakpoint) --------------------------------------------------------

  d.step("the breakpoint collapses the sidebar below 750sp") do
    app.active_window.window_breakpoint.signal_emit("apply")
    app.active_window.then do |window|
      d.check("the split view collapsed") { window.split_view.collapsed? }
      d.check("its sidebar narrowed to 300") { window.split_view.max_sidebar_width == 300 }
      d.check("the sidebar toggle button appeared") { window.show_sidebar_button.visible? }
      d.check("toggle-sidebar is enabled now") { window.window_action("toggle-sidebar").enabled? }
    end
    d.shot("10-collapsed")
  end

  d.step("toggling the sidebar action while collapsed flips show-sidebar") do
    app.active_window.then do |window|
      window.view_stack.visible_child_name = Constrict::ConstrictWindow::QUEUE_PAGE
      starting = window.split_view.show_sidebar?
      window.window_action("toggle-sidebar").activate(nil)
      d.check("show-sidebar flipped") { window.split_view.show_sidebar? == !starting }
      window.window_action("toggle-sidebar").activate(nil)
      d.check("and flips back") { window.split_view.show_sidebar? == starting }
    end
  end

  # A real desktop session would see this uncollapse the sidebar, the way
  # letting go of a resize that crossed back over 750sp would. This Xvfb
  # display itself is narrower than 750sp, though (see the note on "the
  # window builds" above), so libadwaita's own live breakpoint monitor
  # re-evaluates the real width on the very next allocation and reapplies
  # the narrow setters regardless of what "unapply" just set — a ceiling
  # this environment puts on the check, not a question the port's wiring
  # left open. What is still checked is that the signal exists and the
  # setter pairing noted above keeps holding once GTK has had its say.
  d.step("the breakpoint's unapply signal exists and the setter pairing still holds") do
    app.active_window.then do |window|
      d.check("emitting unapply does not raise") do
        window.window_breakpoint.signal_emit("unapply")
        true
      end
      d.check("toggle-sidebar is still enabled exactly when collapsed") do
        window.window_action("toggle-sidebar").enabled? == window.split_view.collapsed?
      end
    end
  end

  # --- 8. Application- and window-level actions and accelerators
  # (application.rb) ----------------------------------------------------------

  d.step("the application registers every action it claims") do
    ["new-window", "quit", "about", "preferences", "shortcuts", "open-dir", "focus-window"].each do |name|
      d.check("app.#{name} exists") { app.app_actions.key?(name) }
    end
    ["toggle-sidebar", "open", "export", "cancel", "clear_all", "close"].each do |name|
      d.check("win.#{name} exists") { app.active_window.window_actions.key?(name) }
    end
  end

  d.step("the application registered upstream's own accelerators") do
    Constrict::Application::WINDOW_ACCELS.merge(
      "app.new-window" => ["<primary>n"], "app.quit" => ["<primary>q"],
      "app.preferences" => ["<primary>comma"],
    ).each do |action, accels|
      d.check("#{action} is #{accels.first}") do
        app.app.get_accels_for_action(action).map { |a| Gtk.accelerator_parse(a) } ==
          accels.map { |a| Gtk.accelerator_parse(a) }
      end
    end
  end

  d.step("app.new-window opens a second, independent window") do
    app.app_actions.fetch("new-window").activate(nil)
  end

  d.step("the second window is up, and the first is untouched") do
    d.check("two windows now") { app.windows.length == 2 }
    d.check("two toplevels") { Gtk::Window.list_toplevels.length == 2 }
    d.check("the new one is active") { app.active_window.equal?(app.windows.first) }
  end

  d.step("app.focus-window brings a window to the front by id, or opens one" \
         " if the id does not match any open window") do
    app.windows.last.id.then do |other_id|
      app.app_actions.fetch("focus-window").activate(GLib::Variant.new(other_id, "i"))
      pump(300)
      d.check("the named window is active now") { app.active_window.id == other_id }
    end

    app.app_actions.fetch("focus-window").activate(GLib::Variant.new(-999, "i"))
    d.check("an id nothing matches opens a third window instead") { app.windows.length == 3 }
  end

  d.step("app.quit closes every window") do
    app.app_actions.fetch("quit").activate(nil)
  end

  d.step("every window closed") do
    pump(300)
    d.check("no windows left") { app.windows.empty? }
  end

  # --- 9. A fresh window for the parts the quit above would otherwise have
  # torn down ------------------------------------------------------------------

  d.step("app.new-window opens a window again for the remaining checks") do
    app.app_actions.fetch("new-window").activate(nil)
  end

  d.step("close-request saves window state when nothing is compressing") do
    app.active_window.then do |window|
      window.target_size_input.value = 42
      d.check("close-request returns false (does not veto the close)") do
        window.signal_emit("close-request") == false
      end
      d.check("the target size was written to settings") { app.settings["target-size"] == 42 }
    end
  end

  # --- 10. Style, Settings, Enums, the CLI parser and i18n: the non-widget
  # halves (style.rb, settings.rb, enums.rb, cli.rb, i18n.rb) -----------------

  d.step("upstream's stylesheet parses with no errors swallowed") do
    [].then do |errors|
      Gtk::CssProvider.new.tap do |provider|
        provider.signal_connect("parsing-error") { |_p, _section, error| errors << error.message }
        provider.load_from_string(Constrict::Style::CSS)
      end
      d.check("the stylesheet parses cleanly") { errors.empty? }
    end
    d.check("it carries the drag-handle rule") { Constrict::Style::CSS.include?(".drag-handle") }
    d.check("it carries the overlay-status rule") { Constrict::Style::CSS.include?(".overlay-status") }
  end

  d.step("Settings round-trips every key through its own JSON file") do
    Dir.mktmpdir("constrict-settings").then do |dir|
      path = File.join(dir, "settings.json")
      Constrict::Settings.new(path: path).then do |settings|
        d.check("defaults answer before anything is written") { settings["target-size"] == 10 }
        settings["target-size"] = 25
        settings.fps_mode = Constrict::FpsMode::PREFER_SMOOTH
        settings.video_codec = Constrict::VideoCodec::AV1
        settings["use-gpu-encoding"] = false
      end

      Constrict::Settings.new(path: path).then do |reloaded|
        d.check("the plain key came back") { reloaded["target-size"] == 25 }
        d.check("the fps-mode enum round-tripped by nickname") do
          reloaded.fps_mode == Constrict::FpsMode::PREFER_SMOOTH
        end
        d.check("so did the video-codec enum") { reloaded.video_codec == Constrict::VideoCodec::AV1 }
        d.check("and a plain boolean") { reloaded["use-gpu-encoding"] == false }
        d.check("the named accessor agrees with the bracket reader") do
          reloaded.target_size == reloaded["target-size"]
        end
      end
    end
  end

  d.step("a settings file nothing can parse falls back to defaults, not a crash") do
    Dir.mktmpdir("constrict-bad-settings").then do |dir|
      path = File.join(dir, "settings.json")
      File.write(path, "{ not json")
      Constrict::Settings.new(path: path).then do |settings|
        d.check("it falls back to the default") { settings["target-size"] == 10 }
      end
    end
  end

  d.step("the enums round-trip through their GSettings-schema nicknames") do
    d.check("auto is the default nick") { Constrict::FpsMode.nick(Constrict::FpsMode::AUTO) == "auto" }
    d.check("and back") { Constrict::FpsMode.from_nick("prefer-clear") == Constrict::FpsMode::PREFER_CLEAR }
    d.check("an unknown nick falls back to auto") { Constrict::FpsMode.from_nick("bogus") == Constrict::FpsMode::AUTO }
    d.check("h264 is the default codec nick") { Constrict::VideoCodec.nick(Constrict::VideoCodec::H264) == "h264" }
    d.check("vp9 round-trips") { Constrict::VideoCodec.from_nick("vp9") == Constrict::VideoCodec::VP9 }
  end

  d.step("the CLI option parser reads upstream's own flags") do
    Constrict::Cli.new(["-i", "in.mp4", "-s", "10", "-o", "out.mp4", "--codec", "av1", "--extra-quality"]).then do |cli|
      cli.send(:parse)
      options = cli.instance_variable_get(:@options)
      d.check("the input path parsed") { options[:file_path] == "in.mp4" }
      d.check("the target size parsed as an integer") { options[:target_size] == 10 }
      d.check("the output path parsed") { options[:output] == "out.mp4" }
      d.check("the codec parsed") { options[:codec] == "av1" }
      d.check("the flag parsed") { options[:extra_quality] == true }
    end

    d.check("a run missing required flags raises rather than silently compressing") do
      begin
        Constrict::Cli.new(["-i", "in.mp4"]).send(:parse)
        false
      rescue OptionParser::MissingArgument
        true
      end
    end

    d.check("the FPS mode table matches the enum") do
      Constrict::Cli::FPS_MODES == {
        "auto" => Constrict::FpsMode::AUTO,
        "prefer-clear" => Constrict::FpsMode::PREFER_CLEAR,
        "prefer-smooth" => Constrict::FpsMode::PREFER_SMOOTH,
      }
    end
  end

  d.step("some pure backend arithmetic that needs no ffmpeg at all") do
    d.check("a 1080p-capable bitrate at 30fps presets to 1080p") do
      Constrict::Utils.res_preset(2_000_000, 1920, 1080, 30.0) == 1080
    end
    d.check("a tiny bitrate presets down, never up") do
      Constrict::Utils.res_preset(50_000, 1920, 1080, 30.0) < 1080
    end
    d.check("h264 at low bitrate picks the slowest preset") do
      Constrict::Utils.h264_speed(false, true, false) == "veryslow"
    end
    d.check("hardware encoding picks the hardware encoder name") do
      Constrict::Utils.video_encoder(Constrict::VideoCodec::H264, true) == "h264_vaapi"
    end
    d.check("software encoding picks the software one") do
      Constrict::Utils.video_encoder(Constrict::VideoCodec::H264, false) == "libx264"
    end
  end

  d.step("the French catalogue translates one of upstream's own msgids") do
    ENV["LANGUAGE"] = "fr"
    Constrict::I18n.instance_variable_set(:@catalog, nil)
    d.check("the Preferences title is no longer the English string") do
      Constrict::I18n._("Preferences") != "Preferences"
    end
  ensure
    ENV.delete("LANGUAGE")
    Constrict::I18n.instance_variable_set(:@catalog, nil)
    d.check("English comes back once the environment does") { Constrict::I18n._("Preferences") == "Preferences" }
  end

  d.step("ticking every counter for a clean shutdown") do
    pump(300)
    app.windows.each(&:close)
  end

  d.step("the application is empty again, exactly as it started") do
    pump(300)
    d.check("no windows left") { app.windows.empty? }
  end
end
