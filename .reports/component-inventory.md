# Component inventory — Constrict (upstream `origin/main`) vs. `lib/` on `ruby`

Scope: every user-facing component (windows, dialogs, pages, rows, menus,
keyboard shortcuts, actions, empty/error states) in upstream's `src/` and
`src/gtk/`, plus the supporting `.blp` files, GSettings schema, GResource
manifest and `po/` catalogue. Upstream is Python + blueprint
(`src/*.py` + `src/*.blp`, compiled to `.ui`/GResource at build time); the
port builds the same widget trees directly in Ruby with no `.ui`/GResource
step, per the house style.

Order follows how a user meets the app: main window → status page → queue
page (sidebar + sources list + row) → dialogs → shortcuts → supporting
infrastructure (settings, style, i18n, CLI).

## Summary

Every upstream component file already has a corresponding `lib/constrict/*.rb`
file on `ruby`, and a reading of each port file shows the widgets, actions and
menus from the matching upstream file/blueprint pair are present. No new
component file is needed; this report is the inventory the task asked for,
not a parity bug list (that is `component-parity`'s job).

## Components

| # | Upstream file(s) | Kind | `lib/*.rb` path | Exists? |
|---|---|---|---|---|
| 1 | `src/main.py` | Application (singleton, app actions: `new-window`, `quit`, `about`, `preferences`, `open-dir`, `focus-window`) | `lib/constrict/application.rb` | Yes |
| 2 | `src/window.blp` + `src/window.py` | Main window (`Adw.ApplicationWindow`): status page, queue page (sidebar settings pane + content pane), breakpoint, toasts, drag-and-drop overlays, menu, export/cancel action bars, window actions (`open`, `export`, `cancel`, `clear_all`, `close`, `toggle-sidebar`) | `lib/constrict/window.rb` | Yes |
| 3 | `src/drag_overlay.blp` + `src/drag_overlay.py` | Composite widget — drag-and-drop reveal overlay (`Adw.Bin` + `Gtk.Overlay` + `Gtk.Revealer` + `Adw.StatusPage`), used by both the status page and the queue page | `lib/constrict/drag_overlay.rb` | Yes |
| 4 | `src/sources_list_box.blp` + `src/sources_list_box.py` | List box of staged video sources (`Gtk.ListBox`, boxed-list style) + "Add Videos…" `Adw.ButtonRow` (`win.open`) | `lib/constrict/sources_list_box.rb` | Yes |
| 5 | `src/sources_row.blp` + `src/sources_row.py` | One source-video row (`Adw.ActionRow`): thumbnail, drag handle, error/broken/incompatible/progress/complete/menu `MenuButton`s + popovers, `row.*` actions (`move-up`, `move-down`, `remove`, `on-error`, `find-compressed-file`), drag source/drop target for reordering | `lib/constrict/sources_row.rb` | Yes |
| 6 | `src/progress_pie.py` | Custom `Gtk.DrawingArea` subclass — circular progress indicator drawn with Cairo, used inside a source row's progress button | `lib/constrict/progress_pie.rb` | Yes |
| 7 | `src/progress_popover_box.blp` + `src/progress_popover_box.py` | Popover content box showing the current attempt plus any prior failed attempts for a row | `lib/constrict/progress_popover_box.rb` | Yes |
| 8 | `src/current_attempt_box.blp` + `src/current_attempt_box.py` | One compression attempt's live progress (heading, target-size label, `Gtk.ProgressBar`, detail label) | `lib/constrict/current_attempt_box.rb` | Yes |
| 9 | `src/attempt_fail_box.blp` + `src/attempt_fail_box.py` | One failed compression attempt's summary (separator, heading, target label, failure icon + wrapped detail label) | `lib/constrict/attempt_fail_box.rb` | Yes |
| 10 | `src/error_dialog.blp` + `src/error_dialog.py` | Error detail dialog (`Adw.Dialog`): toast overlay, read-only monospace `Gtk.TextView`, `dialog.copy-details` action | `lib/constrict/error_dialog.rb` | Yes |
| 11 | `src/preferences_dialog.blp` + `src/preferences_dialog.py` | App preferences dialog (`Adw.PreferencesDialog`): GPU-encoding switch row, custom export-suffix entry row | `lib/constrict/preferences_dialog.rb` | Yes |
| 12 | `src/gtk/shortcuts-dialog.blp` | Keyboard-shortcuts dialog (`Adw.ShortcutsDialog`): Video Management + General sections, 7 shortcut items | `lib/constrict/shortcuts_dialog.rb` | Yes |
| 13 | `src/enums.py` | Shared enums (codec, framerate mode, etc.) used across widgets | `lib/constrict/enums.rb` | Yes |
| 14 | `src/shared.py` | Shared UI helpers (e.g. `update_ui` for cross-thread UI updates) | `lib/constrict/shared.rb` | Yes |
| 15 | `src/constrict_utils.py` | Video-compression logic/back end (ffmpeg invocation, attempt loop) — not itself a widget, but every row/box above reports its state | `lib/constrict/constrict_utils.rb` | Yes |
| 16 | `src/constrict_cli.py` | Command-line entry point | `lib/constrict/cli.rb` | Yes |
| 17 | `data/io.github.wartybix.Constrict.gschema.xml.in` | GSettings schema (target size, framerate mode, codec, extra quality, tolerance, GPU encoding, export suffix, window state) | `lib/constrict/settings.rb` | Yes |
| 18 | `src/gtk/style.css` | App stylesheet (custom CSS classes: `icon-dropshadow`, `drag-handle`, `drop-widget`, `overlay-status`, `background`, etc.) | `lib/constrict/style.rb` | Yes |
| 19 | `po/*.po`, `po/LINGUAS`, `po/POTFILES.in` | Translation catalogue + gettext calls throughout `src/*.py` | `lib/constrict/i18n.rb` | Yes |
| 20 | `data/io.github.wartybix.Constrict.metainfo.xml.in` + about-dialog fields in `src/main.py` (`on_about_action`) | About dialog content (developers, artists, acknowledgement sections, translator credits) | consumed from `lib/constrict/application.rb` (`Adwaita::AboutDialog`) | Yes |
| 21 | `data/io.github.wartybix.Constrict.desktop.in` | Desktop launcher entry (name, icon, actions) — not an in-app widget | n/a (packaging metadata; no `lib/*.rb` owner expected) | N/A |
| 22 | `data/io.github.wartybix.Constrict.service.in` | D-Bus service activation file — not an in-app widget | n/a (packaging metadata) | N/A |
| 23 | `src/constrict.gresource.xml.in` | GResource manifest bundling the `.ui` files — upstream build-time artifact; the port has no `.ui`/GResource step by design | n/a (house style builds widgets directly in Ruby) | N/A |
| 24 | `data/icons/**/*.svg` | App/action icon assets | n/a (referenced by icon name from the Ruby widgets, not ported as code) | N/A |

## Notes

- Every row with `Yes` was confirmed by reading the corresponding `lib/constrict/*.rb`
  file and checking it builds the matching widgets/actions/menus from the
  upstream `.blp`/`.py` pair (e.g. `window.rb`'s `window_actions` map covers
  `open`, `export`, `cancel`, `clear_all`, `close`, `toggle-sidebar`; `sources_row.rb`
  is 825 lines and covers every suffix `MenuButton`, the drag source/target,
  and all five `row.*` actions from `sources_row.blp`).
- Rows 21–24 are packaging/build artifacts with no on-screen widget tree of
  their own; they are listed for completeness per the task's instruction to
  cover GResource manifests, desktop files and icon assets, but have no
  `lib/*.rb` counterpart to check against.
- This is a component *inventory*, not a parity verdict: presence of a port
  file does not by itself prove every CSS class, signal and dynamic behaviour
  (e.g. the progress pie's drawn arc, the row's drag-reorder motion handler)
  is byte-for-byte faithful — that finer-grained check is `component-parity`'s
  job and was out of scope for this survey.
