# Constrict — upstream component inventory

Upstream: `origin/main` (Python + PyGObject + blueprint, GTK4 / libadwaita 1).
Port: the `ruby` branch, `lib/`.

Upstream splits almost every component across two files — a `.blp` holding the
widget tree, CSS classes and signal names, and a `.py` holding the subclass,
the `Gtk.Template.Child`s and the callbacks. Both halves map to **one**
`lib/*.rb` file in the port, so the sections below union them.

Read in the order a user meets the app: application, window, the queue's list
box and rows, the progress popover's three boxes, then the dialogs, then the
non-widget support files.

## Target path convention

The pilot port (`gnome-contacts-rb`) is a flat `lib/<thing>.rb` with top-level
classes. `Constrict-rb` is packaged as a gem: `spec.require_paths = ["lib"]`,
`exe/constrict` does `require "constrict"`, and the one widget file that
already exists is `lib/constrict/application.rb` under `module Constrict`.
This inventory therefore targets `lib/constrict/<thing>.rb`, keeping the
existing namespace rather than contradicting the file that is already on the
branch. See **Open questions** below.

## Totals

| | Upstream | `ruby` branch |
|---|---:|---:|
| Component files (widget-bearing) | 12 | 1 (a placeholder) |
| Blueprint template roots | 10 (9 `template`, 1 named root) | n/a by design |
| Distinct GTK/Adw widget types | 38 | 5 |
| Distinct CSS classes applied | 20 | 0 |
| Menu models | 2 (`primary_menu`, `row_actions`) | 0 |
| Installed actions | 18 | 0 |
| Accelerators | 6 | 0 |
| GSettings keys | 11 (+2 enums) | 0 |
| Custom icons | 10 symbolic SVGs | 0 |
| Translation catalogues | 30 `po/*.po` | 0 |

The port is a status page that says the port has not been written yet. Every
user-facing component below is missing.

---

## src/main.py — the application: actions, accelerators, About, notifications

Not a widget class, but it owns the whole action surface.

| Item | Detail |
|---|---|
| Class | `ConstrictApplication(Adw.Application)`, id `io.github.wartybix.Constrict`, flags `HANDLES_OPEN` |
| Main option | `--new-window` / `-n` |
| Actions | `app.new-window`, `app.quit`, `app.about`, `app.preferences`, `app.open-dir` (param `s`), `app.focus-window` (param `i`) |
| Accelerators | `app.new-window` `<primary>n`; `app.quit` `<primary>q`; `app.preferences` `<primary>comma`; `win.toggle-sidebar` `F9`; `win.open` `<Ctrl>o`; `win.export` `<Ctrl>e`; `win.close` `<Ctrl>w` |
| Widgets | `Adw.AboutDialog` (built with `new_from_appdata`, three acknowledgement sections, developers, artists, copyright, translator-credits), `Gtk.FileLauncher` (`app.open-dir`) |
| CSS | `devel` added to the window when the app id ends `.Devel` |
| Notes | `quit` is overridden to close each window in turn so a compressing window can show its cancel dialog. `do_open` stages the files it is handed. |

Port target: `lib/constrict/application.rb` — **exists, placeholder only.** The
About dialog may deserve its own `lib/constrict/about_dialog.rb`; see Open
questions.

## src/window.blp + src/window.py — the main window, both of its pages

`template $ConstrictWindow: Adw.ApplicationWindow`, 1000×700, min 360×294.
This is by far the largest unit: two `Adw.ViewStackPage`s inside one
`Adw.ViewStack`, each with its own header bar and its own drop target.

### Chrome

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` | 1 | `devel` (conditional) | `close-request` overridden | `do_close_request` shows the cancel dialog while compressing |
| `Adw.Breakpoint` | 1 | — | `max-width: 750sp` | sets `split_view.collapsed`, `max-sidebar-width: 300`, reveals `show_sidebar_button`, and enables `win.toggle-sidebar` |
| `Adw.ToastOverlay` | 1 | — | hosts 4 distinct toasts | see Toasts below |
| `Adw.ViewStack` | 1 | — | — | pages `status_page`, `queue_page` |
| `Adw.ToolbarView` | 3 | — | — | status page, sidebar, queue content |
| `Adw.HeaderBar` | 3 | — | — | |
| `Adw.WindowTitle` | 3 | — | — | two static, `main_view_title` dynamic |
| `Gtk.MenuButton` (primary) | 2 | — | `menu-model: primary_menu` | `open-menu-symbolic`, tooltip "Main Menu" |
| `menu primary_menu` | 1 | — | 4 items | `app.new-window`; `app.preferences`, `app.shortcuts`, `app.about` |

Note `primary_menu` targets **`app.shortcuts`**, which `main.py` never
installs — the shortcuts dialog is reachable from the menu only if that action
is added. The port must install it (see `shortcuts-dialog.blp`).

### Empty state — `status_page` page

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Overlay` | 1 | — | — | |
| `Gtk.ProgressBar` `status_progress_bar` | 1 | `osd` | `set_fraction` while staging | `valign: start` |
| `$DragOverlay` | 1 | — | — | composite, see `drag_overlay.blp` |
| `Adw.StatusPage` | 1 | `drop-widget` | — | `video-encoder-symbolic`, "Compress Videos" / "Drag and drop videos here" |
| `Gtk.DropTarget` `drop_target` | 1 | — | `drop => on_drop` | formats `GdkFileList`, actions `copy` |
| `Gtk.Button` | 1 | `pill`, `suggested-action` | `action-name: win.open` | "_Open…", `can-shrink` |

### Settings sidebar — `queue_page` page, `[sidebar]`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.OverlaySplitView` `split_view` | 1 | — | `show-sidebar` bound bidirectional to `show_sidebar_button.active` | min 300 / max 360 |
| `Adw.PreferencesPage` | 1 | — | — | |
| `Adw.PreferencesGroup` | 4 | — | — | untitled, "Framerate Limit", "Encoding Options", "Advanced Options" |
| `Adw.SpinRow` `target_size_row` | 1 | — | adjustment `value-changed` → `refresh_previews` | title "Target _Size (MiB)", adjustment 1–999999 step 1 page 10 default 10 |
| `Gtk.MenuButton` (help) | 3 | `flat` | `popover show` → `announce(...)` | `help-about-symbolic`, tooltip "More Information" |
| `Gtk.Popover` | 3 | — | `show` | fps / encoding / advanced help |
| `Gtk.Label` (help body) | 3 | — | — | wrap, `max-width-chars` 30 / 30 / 50; text set in `__init__` |
| `Adw.ActionRow` | 3 | — | `activatable-widget` | "_Automatic", "_30 FPS", "_60 FPS" (titles formatted from `'{} FPS'`) with subtitles |
| `Gtk.CheckButton` | 3 | — | `toggled` → `refresh_previews` | one radio group, `auto_check_button` is the group leader and starts active |
| `Adw.ComboRow` `codec_dropdown` | 1 | — | `notify::selected` → `refresh_previews` | `Gtk.StringList` ["H.264", "H.265 (HEVC)", "AV1", "VP9"] |
| `Adw.SwitchRow` `extra_quality_toggle` | 1 | — | `notify::active` → `refresh_previews` | "Extra _Quality" |
| `Adw.SpinRow` `tolerance_row` | 1 | — | adjustment `value-changed` → `refresh_previews` | "_Tolerance (%)", 5–100, schema default 25 |

`Gtk.Adjustment` ×2 (`target_size_input`, `tolerance_input`) are types, not
widgets, but both are settings-bound and signal-connected.

### Queue content — `queue_page` page, `[content]`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.ToggleButton` `show_sidebar_button` | 1 | — | drives `split_view.show-sidebar` | `sidebar-show-symbolic`, "Toggle Settings Pane", active, hidden until the breakpoint |
| `Adw.Banner` `warning_banner` | 1 | — | `set_revealed` from `set_warning_state` | "Issues with video sources — fix before compressing"; announced to the screen reader when revealed |
| `Gtk.Overlay` | 1 | — | — | |
| `Gtk.ProgressBar` `queue_page_progress_bar` | 1 | `osd` | `set_fraction` | |
| `$DragOverlay` | 1 | `drop-widget` | — | second instance |
| `Gtk.DropTarget` `drop_target_queue` | 1 | — | `drop => on_drop` | actions flipped to `NONE` while locked |
| `Adw.PreferencesPage` / `Adw.PreferencesGroup` | 1 / 1 | — | — | group title "Video Sources" |
| `Gtk.Button` `clear_all_button` | 1 | `flat` | `action-name: win.clear_all` | "_Clear All", header-suffix |
| `$SourcesListBox` | 1 | — | — | composite, see below |
| `Gtk.ActionBar` `export_bar` | 1 | — | — | `[bottom]` |
| `Gtk.Button` `export_button` | 1 | `pill`, `suggested-action` | `action-name: win.export` | "_Export To…" |
| `Gtk.ActionBar` `cancel_bar` | 1 | — | — | `[bottom]`, hidden until compressing |
| `Gtk.Button` `cancel_button` | 1 | `pill` | `action-name: win.cancel` | "_Cancel…" |

### Window actions, dialogs, states

| Item | Detail |
|---|---|
| Actions | `win.toggle-sidebar` (starts disabled, enabled by the breakpoint setter), `win.open`, `win.export` (enabled only when sources exist and none are broken/incompatible, disabled when all complete), `win.cancel`, `win.clear_all`, `win.close` |
| File dialogs | `Gtk.FileDialog.open_multiple` with a `Gtk.FileFilter` for `video/*` + `image/gif`, title "Pick Videos", initial folder from `open-initial-folder`; `Gtk.FileDialog.select_folder` for export, initial folder from `export-initial-folder` |
| Cancel dialog | `Adw.AlertDialog` "Stop Compression?" / "Progress made compressing “{}” will be permanently lost", responses `cancel` "_Cancel" and `stop` "_Stop" with `DESTRUCTIVE` appearance; a `quit_on_stop` flag closes the window after stopping |
| Toasts | "Error compressing “{}”" with a "View _Details" button → `ErrorDialog`; "Compression complete"; "Unknown video format “{}”" (one per unsupported mime) |
| Notification | `Gio.Notification` "Compression Complete", category `transfer.complete`, singular/plural bodies, default action `app.focus-window` with the window id, button "Open Export Directory" → `app.open-dir`; withdrawn on close and on any settings change |
| Titles | three forms queued (none / one / n) and two forms compressing (one / `{index}/{total}`), each `ngettext`-pluralised; subtitle "Exporting to {dir}" with `~` substituted for `$HOME` |
| Session inhibit | `Gtk.ApplicationInhibitFlags.SUSPEND | LOGOUT`, reason "Videos are being compressed" |
| Settings bound | `window-width`, `window-height`, `window-maximized`, `target-size`, `extra-quality`, `tolerance` (all `GET | GET_NO_CHANGES`); `fps-mode` and `video-codec` read as enums; all written back in `save_window_state` |
| Controls lock | `set_controls_lock` desensitises the 7 setting rows, disables `win.clear_all` / `win.open` / `win.export`, locks the list box and kills the queue drop target |
| Repeaters | the staging loop builds one `SourcesRow` per accepted file; the compression loop builds one `CurrentAttemptBox` per video and N `AttemptFailBox`es per video |
| Conditional | `warning_banner` revealed only in a warning state; `cancel_bar`/`export_bar` swap on compressing; the sidebar auto-collapses when the queue empties; `view_stack` flips to `status_page` when the last source is removed |

Port target: `lib/constrict/window.rb` — **missing.** This is big enough that
the cancel dialog may want its own file; see Open questions.

## src/sources_list_box.blp + src/sources_list_box.py — the queue list

`template $SourcesListBox: Gtk.ListBox`, `selection-mode: none`.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.ListBox` | 1 | `boxed-list` | — | |
| `Adw.ButtonRow` `add_videos_button` | 1 | — | `action-name: win.open` | `list-add-symbolic`, "Add Vide_os…"; always the last row, and `get_length` is defined as its index |

Behaviour: `remove`/`remove_all` keep the button row; `add_sources` inserts
before it; `move` is remove-then-insert; `update_rows` runs per row and sets
`set_draggable(length > 1 && !locked)`, reveals the drag handle, and enables or
disables `row.move-up` (not first), `row.move-down` (not last) and `row.remove`
(not locked). A `locked` flag mirrors the window's controls lock.

Port target: `lib/constrict/sources_list_box.rb` — **missing.**

## src/sources_row.blp + src/sources_row.py — one video in the queue

`template $SourcesRow: Adw.ActionRow`. The densest component in the app: seven
mutually exclusive suffix widgets driven by a seven-value state machine.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ActionRow` | 1 | — | `install_action` ×5 | `title-lines: 2`, `subtitle-lines: 1`, not selectable; title is the display name, subtitle is the `1080p@60 → 720p@30` preview (reversed for RTL) |
| `Gtk.Image` `thumbnail` | 1 | `icon-dropshadow` | — | `image-loading` → `gst-video-thumbnailer` texture via `Gly`/`GlyGtk4`, falling back to `video-x-generic` or `image-x-generic` |
| `Gtk.Revealer` `drag_handle_revealer` | 1 | — | `reveal-child` | `slide_right` |
| `Gtk.Image` (drag handle) | 1 | `drag-handle` | — | `list-drag-handle-symbolic` |
| `Gtk.Button` `error_icon` | 1 | `error`, `flat` | `action-name: row.on-error` | `error-outline-symbolic`, "View Error Details", hidden unless state `ERROR` |
| `Gtk.MenuButton` `video_broken_button` | 1 | `error`, `flat` | popover `show` → `announce` | `broken-video-symbolic`, hidden unless `BROKEN` |
| `Gtk.Popover` + `Gtk.Label` (broken) | 1 + 1 | — | — | "Cannot load video. It may be missing or corrupted." |
| `Gtk.MenuButton` `incompatible_button` | 1 | **dynamic**: `["flat","error"]` when incompatible, `["flat","warning"]` when warning | popover `show` → `announce` | icon flips `exclamation-mark-symbolic` / `warning-outline-symbolic`, tooltip flips "View Error Details" / "More Information" |
| `Gtk.Popover` + `Gtk.Label` (incompatible) | 1 + 1 | — | — | text set by `set_incompatible` or `set_warning` |
| `Gtk.MenuButton` `progress_button` | 1 | `flat` | popover `show` → `announce` | "View Compression Progress", hidden unless `COMPRESSING` |
| `$ProgressPie` `progress_pie` | 1 | — | `set_fraction` | 16×16 |
| `Adw.Spinner` `progress_spinner` | 1 | — | — | 16×16, swapped in for the pie during VP9 analysis |
| `Gtk.Popover` `progress_popover` + `Gtk.ScrolledWindow` | 1 + 1 | — | `popdown` on completion | hosts `$ProgressPopoverBox` |
| `Gtk.MenuButton` `complete_button` | 1 | `success`, `flat` | popover `show` → `announce` | `check-plain-symbolic`, "More Details", hidden unless `COMPLETE` |
| `Gtk.Popover` + `Gtk.Box` + `Gtk.Label` (complete) | 1+1+1 | — | — | "Video compressed to {size} MiB." |
| `Gtk.Button` (show file) | 1 | — | `action-name: row.find-compressed-file` | "Show File Location" → `Gtk.FileLauncher.open_containing_folder` |
| `Gtk.MenuButton` `menu_button` | 1 | `flat` | `menu-model: row_actions` | `view-more-symbolic`, "View More" |
| `menu row_actions` | 1 | — | 3 items | "Move _Up" `row.move-up`, "Move _Down" `row.move-down`, "_Remove" `row.remove` |

Controllers (behaviour, not widgets): `Gtk.DragSource` `drag_source` —
`prepare => on_drag_prepare`, `drag-begin => on_drag_begin`, propagation phase
toggled `CAPTURE`/`NONE` by `set_draggable`; `Gtk.DropTarget` — actions `move`,
format `SourcesRow`, `preload`, `motion => on_motion`, `drop => on_drop`.
`on_drag_begin` builds a throwaway `Gtk.ListBox` holding a second `SourcesRow`
as the `Gtk.DragIcon` child — a repeater the scan cannot see.

Actions installed: `row.move-up`, `row.move-down`, `row.on-error`,
`row.find-compressed-file`, `row.remove`.

States (`SourceState`): `PENDING`, `COMPRESSING`, `COMPLETE`, `ERROR`,
`BROKEN`, `INCOMPATIBLE`, `WARN`. `BROKEN` and `INCOMPATIBLE` additionally
fire the window's warning action, which blocks export; `WARN` does not.

Port target: `lib/constrict/sources_row.rb` — **missing.**

## src/progress_pie.py — the circular progress indicator

No blueprint; built in code. `class ProgressPie(Gtk.DrawingArea)`, centred
both ways, with a `set_draw_func` that paints a background disc at alpha 0.15
and a foreground pie wedge from −90° using the widget's own `get_color()`.
`set_fraction` stores and queues a redraw.

Port target: `lib/constrict/progress_pie.rb` — **missing.** Needs Cairo
drawing through the Ruby bindings, not a Python `cairo.Context`.

## src/progress_popover_box.blp + src/progress_popover_box.py — the progress popover body

`template $ProgressPopoverBox: Gtk.Box`, vertical, nothing else declared. One
`CurrentAttemptBox` is prepended as `top_widget`, and each `AttemptFailBox` is
inserted after it. `get_message` concatenates every child's labels with
`'... '` for the screen reader.

Port target: `lib/constrict/progress_popover_box.rb` — **missing.**

## src/current_attempt_box.blp + src/current_attempt_box.py — the running attempt

`template $CurrentAttemptBox: Gtk.Box`, vertical, 6px margins. Design
acknowledged from Nautilus' progress info widget.

| Widget | × | CSS | Notes |
|---|---:|---|---|
| `Gtk.Label` `attempt_label` | 1 | `heading` | "Attempt {n}" |
| `Gtk.Label` `target_details_label` | 1 | — | "Initializing…" → "Compressing to {kbps} kbps ({res}p@{fps}, HQ/LQ audio)", `ellipsize: start`, 300px request |
| `Gtk.ProgressBar` `progress_bar` | 1 | — | `set_fraction`, or `pulse` during VP9 analysis |
| `Gtk.Label` `progress_details_label` | 1 | `dim-label`, `numeric` | "0 %" → "{n} %", "{n} % — Almost done", or "{n} % — About {time} left" |

The ETA string is a four-branch, `ngettext`-pluralised ladder (seconds; minutes;
hours + minutes under 4h; hours only above) — a translation surface in its own
right.

Port target: `lib/constrict/current_attempt_box.rb` — **missing.**

## src/attempt_fail_box.blp + src/attempt_fail_box.py — one failed attempt

`template $AttemptFailBox: Gtk.Box`, vertical, `hexpand`.

| Widget | × | CSS | Notes |
|---|---:|---|---|
| `Gtk.Separator` | 1 | — | |
| `Gtk.Box` | 2 | — | outer vertical, inner horizontal 300px |
| `Gtk.Label` `attempt_label` | 1 | `heading` | "Attempt {n}" |
| `Gtk.Label` `target_label` | 1 | `dimmed` | "{kbps} kbps ({res}p@{fps}, HQ/LQ audio)" |
| `Gtk.Image` `failure_icon` | 1 | — | `arrow2-up-symbolic` when too large, `arrow2-down-symbolic` when too small |
| `Gtk.Label` `failure_details_label` | 1 | — | "Compressed file size was too large/small ({size} MiB)", wrap `word_char`, 40 chars |

Port target: `lib/constrict/attempt_fail_box.rb` — **missing.**

## src/drag_overlay.blp + src/drag_overlay.py — the drop-hint overlay

`template $DragOverlay: Adw.Bin`. Design acknowledged from Loupe. Used twice
(status page and queue page).

| Widget | × | CSS | Notes |
|---|---:|---|---|
| `Adw.Bin` (template) | 1 | — | exposes `child` and `drop_target` as GObject properties |
| `Gtk.Overlay` `overlay` | 1 | — | `child` property proxies to it |
| `Gtk.Revealer` `revealer` | 1 | — | `CROSSFADE`, `can-target: false`, revealed by `notify::current-drop` on the assigned drop target |
| `Adw.Bin` | 1 | `background` | |
| `Adw.StatusPage` | 1 | `overlay-status` | "Drop Videos to Import", `video-x-generic-symbolic` |

Port target: `lib/constrict/drag_overlay.rb` — **missing.** The two custom
properties (`child`, `drop_target`) are the quirky part under the Ruby
bindings.

## src/error_dialog.blp + src/error_dialog.py — compression error details

`template $ErrorDialog: Adw.Dialog`, 600×450, title "Compression Error".

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.Dialog` | 1 | — | `install_action('dialog.copy-details')` | |
| `Adw.ToolbarView` + `Adw.HeaderBar` | 1 + 1 | — | — | |
| `Adw.ToastOverlay` | 1 | — | — | hosts "Details copied to clipboard" |
| `Adw.PreferencesPage` `preference_page` | 1 | — | — | description "There was a problem compressing “{}”", markup-escaped |
| `Adw.PreferencesGroup` | 1 | — | — | title "Details" |
| `Gtk.Button` `copy_button` | 1 | `flat` | `action-name: dialog.copy-details` | `edit-copy-symbolic`, "Copy Details" |
| `Gtk.ScrolledWindow` | 1 | `card` | — | `overflow: hidden`, `vexpand` |
| `Gtk.TextView` `text_view` | 1 | `monospace`, `inline` | — | read-only, 12px margins, `word_char` wrap; buffer holds the ffmpeg error text |

Port target: `lib/constrict/error_dialog.rb` — **missing.**

## src/preferences_dialog.blp + src/preferences_dialog.py — preferences

`template $PreferencesDialog: Adw.PreferencesDialog`, title "Preferences",
`content-height: 425`.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.PreferencesDialog` | 1 | — | — | shows its own toast "Changes applied" |
| `Adw.PreferencesPage` | 1 | — | — | |
| `Adw.PreferencesGroup` `hw_accel_group` | 1 | — | — | "Hardware Acceleration" + a long description mentioning 360p |
| `Adw.SwitchRow` `gpu_encoding_row` | 1 | — | bound to `use-gpu-encoding` (`DEFAULT`) | "GPU Encoding" |
| `Adw.PreferencesGroup` `suffix_group` | 1 | — | — | "Exported Video Suffix" + a description naming the default suffix |
| `Adw.EntryRow` `suffix_entry_row` | 1 | — | `apply` → writes `custom-export-suffix` | `show-apply-button`, "Custom Suffix" |

The default suffix is `" (compressed)"`, built on the application and
translated; both this dialog and the export path read it.

Port target: `lib/constrict/preferences_dialog.rb` — **missing.**

## src/gtk/shortcuts-dialog.blp — the keyboard shortcuts dialog

A standalone blueprint with **no backing Python file** and a named root rather
than a `template`: `Adw.ShortcutsDialog shortcuts_dialog`. Nothing on
`origin/main` loads it and no `app.shortcuts` action exists, although
`primary_menu` points at one — so the port both ports the dialog and installs
the action.

| Section | Items (`Adw.ShortcutsItem`) |
|---|---|
| "Video Management" | Open → `win.open`; Export → `win.export` |
| "General" | Toggle Settings Pane → `win.toggle-sidebar`; Show Shortcuts → `app.shortcuts`; Close Window → `win.close`; Quit → `app.quit`; Show Preferences → `app.preferences` |

Titles use the `shortcut window` gettext context (`C_(...)`).

Port target: `lib/constrict/shortcuts_dialog.rb` — **missing.** The pilot port
has a worked equivalent in `gnome-contacts-rb/lib/shortcuts_dialog.rb`.

---

## Non-widget files that the components depend on

| Upstream | Port target | Kind | Present | Notes |
|---|---|---|---|---|
| `src/gtk/style.css` | `lib/constrict/style.rb` (inline CSS loaded via `Gtk::CssProvider`) | stylesheet | no | defines `.drag-handle`, `.drag-handle:backdrop`, `.overlay-status`, `.overlay-status label`, `.drop-widget`. All five are applied; the other 15 classes in use are stock Adwaita |
| `data/io.github.wartybix.Constrict.gschema.xml.in` | `lib/constrict/settings.rb` | GSettings schema | no | 11 keys + the `FpsMode` and `VideoCodec` enums. Note `tolerance` defaults to **25** in the schema while the blueprint adjustment says 10, and the advanced-help string interpolates the schema default |
| `src/enums.py` | `lib/constrict/enums.rb` | enums | no | `FpsMode` (3), `VideoCodec` (4), `SourceState` (7) |
| `src/shared.py` | `lib/constrict/shared.rb` | helper | no | `get_tmp_dir`, and `update_ui` — the GLib.idle_add-vs-direct-call shim threaded through every setter above. Ruby will want a different shape for this |
| `src/constrict_utils.py` | `lib/constrict/constrict_utils.rb` | backend (994 lines) | no | ffmpeg/ffprobe driver: `compress`, `transcode`, `get_encode_settings`, resolution/framerate/duration/audio probes, `get_progress`, `will_ha_work`, subtitle streams. No UI, but every progress and failure string above comes from its callbacks |
| `src/constrict_cli.py` | `lib/constrict/cli.rb` | CLI | no | `constrict-cli` with `-i -s -t -o --framerate --extra-quality --codec --software-encode`, plus its own terminal progress output. A separate user-facing surface |
| `src/constrict.gresource.xml.in` | n/a — plus an icon search path | GResource manifest | no | the 10 `.ui` entries have no Ruby equivalent (the house style builds widgets in code); the 10 icon entries do need loading |
| `data/icons/scalable/actions/*.svg` | `data/icons/` + `Gtk::IconTheme#add_search_path` | assets | no | `video-encoder`, `error-outline`, `broken-video`, `exclamation-mark`, `warning-outline`, `check-plain`, `arrow2-down`, `arrow2-up`, `list-drag-handle`, `help-about` — all symbolic, all referenced by name above |
| `po/*.po` (30 languages), `po/LINGUAS`, `po/POTFILES.in` | `po/` + `lib/constrict/i18n.rb` | translations | no | upstream marks strings in 11 `.py`/`.blp` files plus the desktop, metainfo and gschema files, and uses `ngettext` in 4 places and `C_` in one |

---

## Open questions

1. **`lib/<thing>.rb` vs `lib/constrict/<thing>.rb`.** The brief says
   `lib/<thing>.rb` and the pilot port is flat with top-level classes; this
   repo is a gem whose only existing widget file is
   `lib/constrict/application.rb` under `module Constrict`, which
   `exe/constrict` already calls as `Constrict::Application`. This inventory
   assumes the gem layout. If the flat layout is wanted instead, the existing
   file and `exe/constrict` both have to move.
2. **Components with no upstream file of their own.** The cancel
   `Adw.AlertDialog` and the `Adw.AboutDialog` are built inline in `window.py`
   and `main.py`. One-file-per-upstream-file puts them in `window.rb` and
   `application.rb`; `window.rb` is already the largest unit by a wide margin,
   so splitting the cancel dialog into `lib/constrict/cancel_dialog.rb` is
   worth deciding before the window is written.
3. **`update_ui`'s threading model.** Upstream passes a `daemon` boolean
   through roughly forty setters to choose between a direct call and
   `GLib.idle_add`. Upstream's own comment calls it code that should be
   replaced. The port needs one decision here before any of the progress
   components are written, because the flag is in almost every signature.
4. **Thumbnails depend on `Gly`/`GlyGtk4` and the `gst-video-thumbnailer`
   binary.** Whether the Ruby bindings and the dev shell can supply those
   decides whether `sources_row.rb` gets real thumbnails or only the generic
   icon fallback.
5. **`app.shortcuts` does not exist upstream.** The menu item and the
   shortcuts dialog are both dead on `origin/main`. The port should install
   the action — flagged here so it does not read as an unexplained extra.
