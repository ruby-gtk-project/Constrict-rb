# frozen_string_literal: true

require "adwaita"

require_relative "i18n"

module Constrict
  # Ported from upstream's src/gtk/shortcuts-dialog.blp.
  #
  # Upstream's blueprint is a standalone named root rather than a template, so
  # it has no Python file behind it; this class is the whole component. Each
  # item names an action rather than an accelerator, and libadwaita looks the
  # accelerator up from the application — so the shortcuts listed here are
  # whatever Application and ConstrictWindow actually bind.
  # Adw.ShortcutsDialog is a final GType, so this composes one rather than
  # subclassing it: #build returns the dialog, and #present forwards to it.
  class ShortcutsDialog
    include I18n

    # Upstream marks these titles with the "shortcut window" gettext context,
    # so translators can shorten them for this dialog without affecting the
    # same words elsewhere. They are stored untranslated and passed through
    # C_() as the dialog is built.
    SECTIONS = {
      "Video Management" => [
        ["Open", "win.open"],
        ["Export", "win.export"],
      ],
      "General"          => [
        ["Toggle Settings Pane", "win.toggle-sidebar"],
        ["Show Shortcuts", "app.shortcuts"],
        ["Close Window", "win.close"],
        ["Quit", "app.quit"],
        ["Show Preferences", "app.preferences"],
      ],
    }.freeze

    def build
      dialog.tap do |shortcuts|
        # The title is left alone: upstream's blueprint does not set one
        # either, so libadwaita's own translated default stands.
        SECTIONS.each { |title, items| shortcuts.add(section(title, items)) }
      end
    end

    def present(parent) = build.present(parent)

    def dialog = @dialog ||= Adwaita::ShortcutsDialog.new

    private

      def section(title, items)
        Adwaita::ShortcutsSection.new.tap do |section|
          section.title = C_("shortcut window", title)
          items.each { |label, action| section.add(item(label, action)) }
        end
      end

      # The constructor demands both a title and an accelerator positionally —
      # keyword arguments fail — so the accelerator is passed empty and the
      # action name set afterwards, which is what upstream's blueprint does.
      def item(label, action)
        Adwaita::ShortcutsItem.new(C_("shortcut window", label), "").tap do |item|
          item.action_name = action
        end
      end
  end
end
