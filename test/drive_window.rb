# frozen_string_literal: true

# Builds the whole window tree under a virtual display, exercises the parts a
# screenshot would not reach, and exits. Run with:
#   nix develop --command xvfb-run -a ruby test/drive_window.rb
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "constrict"
require "constrict/cli"
require "tmpdir"

Dir.mktmpdir do |config_dir|
  ENV["XDG_CONFIG_HOME"] = config_dir

  Constrict::Application.new(app_id: "org.rubygtkproject.ConstrictDrive").then do |application|
    application.build.tap do |app|
      app.signal_connect("activate") do
        Constrict::ConstrictWindow.new(application).tap do |window|
          # Presented first: Gtk::Widget#visible? is ancestor-aware, so
          # nothing inside an unpresented window reports itself visible.
          window.present
          puts "window built: #{window.title.inspect}"
          puts "stack pages: #{window.view_stack.pages.n_items}"
          puts "queue length: #{window.sources_list_box.length}"
          puts "export enabled: #{window.window_action("export").enabled?}"

          window.view_stack.visible_child_name = "queue_page"
          puts "visible: #{window.view_stack.visible_child_name}"

          row = Constrict::SourcesRow.new(video_path: "/nonexistent.mp4", display_name: "demo.mp4")
          window.sources_list_box.add_sources([row])
          puts "queue length after add: #{window.sources_list_box.length}"
          puts "row state: #{row.state}"
          row.set_state(Constrict::SourceState::COMPRESSING, false)
          puts "progress button visible: #{row.progress_button.visible?}"
          row.initiate_popover_box(Constrict::CurrentAttemptBox.new, false)
          row.popover_box.top_widget.set_progress(0.5, 90, false)
          row.set_fraction(0.5, false)
          puts "popover message: #{row.popover_box.message}"
          row.add_attempt_fail(
            attempt_no:            1,
            vid_bitrate:           800_000,
            is_hq_audio:           true,
            vid_height:            720,
            vid_fps:               30.0,
            compressed_size_bytes: 12 * 1024 * 1024,
            target_size_bytes:     10 * 1024 * 1024,
            daemon:                false,
          )
          puts "fail widgets: #{row.popover_box.fail_widgets.length}"
          row.set_complete("/tmp/demo (compressed).mp4", 9.4, false)
          puts "complete label: #{row.complete_label.label}"

          window.sources_list_box.set_locked(true, false)
          puts "locked: #{window.sources_list_box.locked}"
          window.sources_list_box.set_locked(false, false)

          Constrict::ErrorDialog.new("demo.mp4", "ffmpeg: no such file").then do |dialog|
            puts "error dialog: #{dialog.title.inspect} #{dialog.text_view.buffer.text.inspect}"
          end

          Constrict::PreferencesDialog.new(application.settings, application.default_suffix).then do |dialog|
            puts "preferences: #{dialog.title.inspect} gpu=#{dialog.gpu_encoding_row.active?}"
          end

          Constrict::ShortcutsDialog.new.build.then { |dialog| puts "shortcuts: #{dialog.title.inspect}" }

          # Without ffprobe on PATH every property read fails, which is the
          # same signal a corrupted file gives: the row goes BROKEN.
          Constrict::SourcesRow.new(video_path: "/nonexistent.mp4", display_name: "gone.mp4").then do |broken|
            broken.set_preview(-> { 10 }, -> { Constrict::FpsMode::AUTO }, false)
            puts "broken row state: #{broken.state}"
          end

          puts "cli fps modes: #{Constrict::Cli::FPS_MODES.keys.join(",")}"
          Constrict::Utils.res_preset(
            2_000_000,
            1920,
            1080,
            30.0,
          ).then do |preset|
            puts "res preset for 1080p at 2 Mbps: #{preset}"
          end

          window.save_window_state
          puts "settings written to #{application.settings.location}"
          puts "icon lookup: #{Gtk::IconTheme.get_for_display(Gdk::Display.default).has_icon?("video-encoder-symbolic")}"

          app.quit
        end
      end
    end.run([])
  end
end
