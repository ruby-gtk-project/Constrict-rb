# frozen_string_literal: true

require "gtk4"
require "adwaita"

require_relative "preferences_dialog"
require_relative "settings"
require_relative "shortcuts_dialog"
require_relative "style"
require_relative "window"

module Constrict
  # Ported from upstream's src/main.py.
  #
  # The application singleton: it owns the settings every window reads, the
  # application-wide actions the primary menu points at, and the accelerators
  # the shortcuts dialog lists. Windows are not singletons — `app.new-window`
  # opens another, carrying the settings the last one was left on.
  class Application
    APP_ID = "org.rubygtkproject.Constrict"

    # Upstream reads these from its appdata; the port carries them here.
    VERSION = "26.1"
    DEVELOPERS = [
      "Wartybix https://gitlab.gnome.org/wartybix",
      "Philipp Kosarev https://github.com/PhilippKosarev",
      "MoonlightWave-12 https://gitlab.gnome.org/MoonlightWave-12",
    ].freeze

    # The sections upstream credits in its about dialog, kept because the code
    # they credit is in this port too.
    ACKNOWLEDGEMENTS = {
      "‘8mb’ repository by"                   => [
        "Matthew Baggett https://github.com/matthewbaggett/",
        "Ethan Martin https://github.com/yuckdevchan",
      ],
      "Circular progress indicator design by" => [
        "Christian Hergert https://gitlab.gnome.org/chergert",
      ],
      "Drag overlay design by"                => [
        "Sophie Herold https://gitlab.gnome.org/sophie-h",
        "Sam Hewitt https://gitlab.gnome.org/snwh",
      ],
    }.freeze

    # Accelerators for actions the windows own, set here because accelerators
    # are application-wide.
    WINDOW_ACCELS = {
      "win.toggle-sidebar" => ["F9"],
      "win.open"           => ["<Ctrl>o"],
      "win.export"         => ["<Ctrl>e"],
      "win.close"          => ["<Ctrl>w"],
    }.freeze

    attr_reader :settings

    def initialize(app_id: APP_ID, settings: nil)
      @app_id = app_id
      @settings = settings || Settings.new
    end

    def build
      app.tap do
        app.signal_connect("startup") { Style.load }

        app.signal_connect("activate") do
          app.active_window.then do |window|
            if window
              window.present
            else
              new_window
            end
          end
        end

        # HANDLES_OPEN: `constrict video.mp4` stages the files in a new window
        # rather than being rejected as unknown arguments.
        app.signal_connect("open") do |_, files, _hint|
          new_window(files)
        end

        app_actions.each { |_name, action| app.add_action(action) }

        accels.each { |name, keys| app.set_accels_for_action(name, keys) }
      end
    end

    def run = app.run([])

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the windows are Adwaita.
    def app
      @app ||= Gtk::Application.new(@app_id, :handles_open)
    end

    # The suffix exported files get when the user has set no custom one.
    def default_suffix = " (compressed)"

    # The application-level services the windows need. Upstream's windows call
    # these on the GtkApplication they belong to; here they go through the
    # object that owns it.
    def active_window = app.active_window
    def windows = app.windows
    def inhibit(window, flags, reason) = app.inhibit(window, flags, reason)
    def uninhibit(cookie) = app.uninhibit(cookie)
    def send_notification(id, notification) = app.send_notification(id, notification)
    def withdraw_notification(id) = app.withdraw_notification(id)

    def app_actions
      @app_actions ||= {
        "new-window"   => action("new-window") { new_window },
        "quit"         => action("quit") { quit },
        "about"        => action("about") { show_about },
        "preferences"  => action("preferences") { show_preferences },
        "shortcuts"    => action("shortcuts") { show_shortcuts },
        "open-dir"     => parameterised_action("open-dir", "s") { |path| open_dir(path) },
        "focus-window" => parameterised_action("focus-window", "i") { |id| focus_window(id) },
      }
    end

    def accels
      @accels ||= WINDOW_ACCELS.merge(
        "app.new-window"  => ["<primary>n"],
        "app.quit"        => ["<primary>q"],
        "app.preferences" => ["<primary>comma"],
      )
    end

    # Opens a window, optionally with videos already staged. The window that
    # was active writes its state first, so the new one opens on the same
    # compression settings.
    def new_window(files = [])
      app.active_window&.save_window_state

      ConstrictWindow.new(self).tap do |window|
        unless files.empty?
          Thread.new { window.stage_videos(files) }
        end

        window.present
      end
    end

    # Closes every window rather than terminating, so a window that is still
    # compressing gets to show its cancel dialog.
    def quit
      app.windows.each(&:close)
    end

    private

      def action(name)
        Gio::SimpleAction.new(name).tap do |simple_action|
          simple_action.signal_connect("activate") { yield }
        end
      end

      def parameterised_action(name, type)
        Gio::SimpleAction.new(name, GLib::VariantType.new(type)).tap do |simple_action|
          simple_action.signal_connect("activate") do |_, parameter|
            yield(parameter.value)
          end
        end
      end

      # Opens the export directory in the user's file manager, from the button
      # on the "Compression Complete" notification.
      def open_dir(path)
        Gtk::FileLauncher.new(Gio::File.new_for_path(path)).launch
      end

      # Brings a window to the front from the notification's default action.
      def focus_window(window_id)
        app.windows.find { |window| window.id == window_id }.then do |window|
          if window
            window.present
          else
            new_window
          end
        end
      end

      def show_preferences
        PreferencesDialog.new(@settings, default_suffix).present(app.active_window)
      end

      def show_shortcuts
        ShortcutsDialog.new.present(app.active_window)
      end

      def show_about
        about_dialog.present(app.active_window)
      end

      def about_dialog
        Adwaita::AboutDialog.new.tap do |dialog|
          dialog.application_name = "Constrict"
          dialog.application_icon = "video-encoder-symbolic"
          dialog.version = VERSION
          dialog.developer_name = "Wartybix"
          dialog.copyright = "© 2025 Wartybix"
          dialog.license_type = Gtk::License::GPL_3_0
          dialog.developers = DEVELOPERS
          dialog.artists = ["Jakub Steiner <jimmac@gmail.com>"]
          dialog.issue_url = "https://github.com/ruby-gtk-project/Constrict-rb/issues"

          ACKNOWLEDGEMENTS.each do |title, names|
            dialog.add_acknowledgement_section(title, names)
          end
        end
      end
  end
end
