# frozen_string_literal: true

require "adwaita"

module Constrict
  # Ported from upstream's src/gtk/style.css.
  #
  # Upstream ships the stylesheet in its GResource bundle and GTK picks it up
  # from there; a Ruby port has no bundle, so the same three rules are loaded
  # into the default display as an application-level CSS provider.
  module Style
    # The `.drag-handle` rules come from GNOME Settings, and `.overlay-status`
    # and `.drop-widget` from Loupe, as upstream's comments record.
    CSS = <<~CSS
      .drag-handle {
        color: color-mix(in srgb, var(--window-fg-color) 40%, transparent);
      }

      .drag-handle:backdrop {
        color: color-mix(in srgb, var(--window-fg-color) 40%, transparent);
      }

      .overlay-status {
        color: var(--accent-color);
        background-color: color-mix(in srgb, var(--accent-bg-color) 8%, transparent);
        border: 2px dashed color-mix(in srgb, currentColor var(--dim-opacity), transparent);
        border-radius: 2px;
        margin: 12px;
      }

      .overlay-status label {
        opacity: var(--dim-opacity);
      }

      .drop-widget {
        box-shadow: none;
      }
    CSS

    module_function

    # Adds the stylesheet to the display, and the port's icon directory to the
    # icon theme's search path so the ten custom symbolic icons upstream keeps
    # in its GResource bundle resolve by name.
    def load
      Gdk::Display.default.then do |display|
        if display
          Gtk::StyleContext.add_provider_for_display(
            display,
            provider,
            Gtk::StyleProvider::PRIORITY_APPLICATION,
          )
          Gtk::IconTheme.get_for_display(display).add_search_path(icon_dir)
        end
      end
    end

    def provider
      Gtk::CssProvider.new.tap { |css| css.load_from_data(CSS) }
    end

    # data/icons holds `scalable/actions/*.svg`, which is the layout
    # Gtk::IconTheme#add_search_path expects.
    def icon_dir = File.expand_path("../../data/icons", __dir__)
  end
end
