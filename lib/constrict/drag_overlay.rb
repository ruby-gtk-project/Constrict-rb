# frozen_string_literal: true

require "adwaita"

module Constrict
  # Ported from upstream's src/drag_overlay.blp and src/drag_overlay.py.
  #
  # Wraps a widget and fades a "Drop Videos to Import" status page over it
  # while a drag is hovering. Upstream's attribution stands: it came to
  # Constrict from Showtime, which took it from Loupe.
  #
  # Both of upstream's GObject properties are here as plain accessors: `child`
  # is the content under the overlay, and `drop_target` is the target whose
  # `current-drop` drives the reveal. Setting the child has to reach past this
  # class's own override to put the overlay into the Bin, which is what the
  # bind_call below does.
  class DragOverlay < Adwaita::Bin
    type_register

    BIN_CHILD = Adwaita::Bin.instance_method(:child=)

    attr_reader :drop_target

    def initialize
      super
      build
    end

    def build
      tap do
        BIN_CHILD.bind_call(self, overlay)

        overlay.tap { |ovl| ovl.add_overlay(revealer) }

        revealer.tap { |rev| rev.child = hint_bin }

        hint_bin.tap { |bin| bin.child = status_page }
      end
    end

    # The usual content, shown under the overlay.
    def child = overlay.child

    def child=(widget)
      overlay.child = widget
    end

    # Revealing the hint is the only thing the target is watched for; the drop
    # itself is handled by whoever owns the target.
    def drop_target=(target)
      @drop_target = target

      if target
        target.signal_connect("notify::current-drop") do
          revealer.reveal_child = !target.current_drop.nil?
        end
      end
    end

    def overlay = @overlay ||= Gtk::Overlay.new

    def revealer
      @revealer ||= Gtk::Revealer.new.tap do |rev|
        rev.can_target = false
        rev.transition_type = :crossfade
        rev.reveal_child = false
      end
    end

    def hint_bin
      @hint_bin ||= Adwaita::Bin.new.tap { |bin| bin.add_css_class("background") }
    end

    def status_page
      @status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.title = "Drop Videos to Import"
        page.icon_name = "video-x-generic-symbolic"
        page.add_css_class("overlay-status")
      end
    end
  end
end
