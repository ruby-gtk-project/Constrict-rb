# frozen_string_literal: true

require "adwaita"

require_relative "i18n"

module Constrict
  # Ported from upstream's src/preferences_dialog.blp and
  # src/preferences_dialog.py.
  #
  # Two preferences that belong to the application rather than to a window:
  # whether to use the GPU when it can, and the suffix exported files get.
  #
  # Upstream binds the switch straight to GSettings. This port's settings are a
  # JSON file rather than a GSettings schema, so the switch's state is written
  # on `notify::active` and read back when the dialog is built — the same
  # two-way behaviour, without the binding.
  class PreferencesDialog < Adwaita::PreferencesDialog
    include I18n

    type_register

    # The resolution floor below which hardware encoding is never used, as the
    # help text explains.
    HA_FLOOR = "360p"

    def initialize(settings, default_suffix)
      super()
      @settings = settings
      @default_suffix = default_suffix
      build
    end

    def build
      tap do |dialog|
        dialog.title = _("Preferences")
        # Upstream notes this height is a workaround for a libadwaita sizing
        # bug, not a design choice.
        dialog.content_height = 425
        dialog.add(preferences_page)

        preferences_page.tap do |page|
          page.add(hw_accel_group)
          page.add(suffix_group)

          hw_accel_group.tap { |group| group.add(gpu_encoding_row) }
          suffix_group.tap { |group| group.add(suffix_entry_row) }

          gpu_encoding_row.tap do |row|
            row.active = @settings["use-gpu-encoding"]
            row.signal_connect("notify::active") do
              @settings["use-gpu-encoding"] = row.active?
            end
          end

          suffix_entry_row.tap do |row|
            row.text = @settings["custom-export-suffix"]
            row.signal_connect("apply") { update_custom_suffix(row.text) }
          end
        end
      end
    end

    def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new

    def hw_accel_group
      @hw_accel_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Hardware Acceleration")
        group.description = interpolate(
          _(
            "Hardware acceleration is only used if your GPU supports " \
            "encoding with the selected video codec. Additionally, it’s only " \
            "used when compressing to {} or higher, with “Extra Quality” " \
            "disabled.",
          ),
          HA_FLOOR,
        )
      end
    end

    def gpu_encoding_row
      @gpu_encoding_row ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = _("GPU Encoding")
        row.subtitle = _("Use the GPU to speed up encoding when available")
      end
    end

    def suffix_group
      @suffix_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Exported Video Suffix")
        group.description = interpolate(
          _(
            "Used in file names for exported videos, between the base name " \
            "and extension. If the custom suffix is left empty, the default " \
            "suffix of “{}” will be used.",
          ),
          @default_suffix,
        )
      end
    end

    def suffix_entry_row
      @suffix_entry_row ||= Adwaita::EntryRow.new.tap do |row|
        row.title = _("Custom Suffix")
        row.show_apply_button = true
      end
    end

    private

      def update_custom_suffix(text)
        @settings["custom-export-suffix"] = text
        add_toast(Adwaita::Toast.new(_("Changes applied")))
      end
  end
end
