# Component parity — Constrict

| | |
|---|---|
| Upstream | `main` @ `ecd8b7d` |
| Port | `ruby` @ `4ba7d7a` |
| Units with full parity | 9 / 16 widget units (see below); 2 app-level units carry confirmed gaps; source row carries a new text-axis regression introduced this round (widget/behaviour axis still parity) |

## Method

`component-scan.sh` run over both trees (`.reports/` raw TSVs not committed —
reproduce with the `component-identification` skill's scripts). Every delta
the scan reported was read by hand against the source, per that skill's
rule that the scan is a lead, never a verdict.

## Unit: main window — `src/window.blp` + `src/window.py` → `lib/constrict/window.rb`

The raw scan shows apparent gaps of 2 `Adw.ActionRow`, 1 `Adw.AlertDialog`, 1
`Gtk.Button`, 2 `Gtk.CheckButton`, 3 `Gtk.MenuButton`, 1 `Gtk.ProgressBar`.
**All resolve to parity on reading:**

| Widget | Up × | Port × (textual) | Port × (actual, after reading factories) | Verdict |
|---|---:|---:|---:|---|
| `Adw.ActionRow` | 3 | 1 | 3 — `auto_row`/`clear_row`/`smooth_row` each call the shared `check_row` helper (`window.rb:375-397,754-762`) | parity |
| `Gtk.CheckButton` | 3 (the 4th scan hit upstream is a `type() is Gtk.CheckButton` type-check in `window.py:328`, not a constructor — struck) | 2 | 3 — `auto_check_button` direct + `clear_check_button`/`smooth_check_button` each call `grouped_check_button` (`window.rb:406-414,747-752`) | parity |
| `Gtk.MenuButton` | 5 (2 primary-menu + 3 help) | 2 | 5 — `menu_button` called at `primary_menu_button`/`sidebar_menu_button` (window.rb:283-284); `help_button` called at `fps_help_button`/`enc_options_help_button`/`adv_options_help_button` (window.rb:468,484,502) | parity |
| `Gtk.Button` | 4 (open/clear_all/export/cancel) | 3 | 4 — `open_button` + `clear_all_button` direct, `pill_button` called for `export_button` and `cancel_button` (window.rb:266-276,324-346,735-745) | parity |
| `Gtk.ProgressBar` | 2 | 1 | 2 — `osd_progress_bar` called at `status_progress_bar`/`queue_page_progress_bar` (window.rb:280-281,719-724) | parity |
| `Adw.AlertDialog` | 1 (the 2nd scan hit upstream, `window.py:574`, is a parameter type annotation `dialog: Adw.AlertDialog`, not an instantiation — struck) | 1 (`show_cancel_dialog`, window.rb:999-1015) | — | parity |

Driven: the drive harness (`test/drive_constrict.rb`) exercises the
breakpoint collapse/expand, the sidebar toggle, the cancel-confirmation
dialog (named video + choosing "stop"), the primary menu, and the window
actions/accelerators — all `ok` in a 188/188 run (150/150 at the time this
section was first written; the suite grew by 38 checks this round — a real
glycin image-decode test on `SourcesRow` and a harness-bug fix, see
`test-parity.md` — neither of which touches this unit). **Not driven**: the
three FPS/help popovers' own `show` announcement (`help_popover`,
window.rb:779-786) and the three preference rows under "Advanced
Options"/"Encoding Options" beyond their mere existence. Minor, noted for
completeness.

**Verdict: parity**, once the scan's factory/false-positive noise is read
through. This unit does not deserve the raw scan's apparent 10-widget gap.

## Unit: source row — `src/sources_row.blp` + `.py` → `lib/constrict/sources_row.rb`

Raw scan also shows a `css warning` "extra" in the port with none upstream.
**False positive**: upstream's `set_warning` (`sources_row.py:465-476`) does
apply `["flat", "warning"]` — it's a Python list literal, which the
blueprint-oriented scan regex does not catch in `.py` files. Correspondence,
not an extra.

MenuButton/Popover count (5 `Gtk.MenuButton`, 4 `Gtk.Popover` in the port vs.
5/0 upstream scan) is the standard menu-button-plus-popover pattern upstream
expresses as `[prefix suffix] MenuButton { popover: Popover {...} }` inline in
the blueprint, which the scan does read for `Gtk.MenuButton` but not for the
nested `Popover`/`Label` objects declared without an explicit `Gtk.` prefix
(see `component-identification`'s "bare blueprint declarations" under-report).
Read by hand: the row's five suffix menu buttons (broken/incompatible,
progress, complete, error, generic overflow) and their four popovers all have
a port counterpart. **Verdict: parity.**

## Unit: About dialog content — `main.py` (`on_about_action`) + `data/*.metainfo.xml.in` → `lib/constrict/application.rb`

**Gap, confirmed by reading, not by the scan** (the scan does not carry
string values at all — this is the text axis, and the four-widget axes pass):

1. **Reworded msgid** (text axis — flagged in both this report and
   `translation-parity.md`). Upstream:

   ```python
   _('‘{}’ repository by').format('8mb')
   ```

   — the msgid translators have is the *template* `‘{}’ repository by`. The
   port (`application.rb:37`) hardcodes the substituted result as the msgid
   itself:

   ```ruby
   "‘8mb’ repository by" => [ ... ]
   ```

   That is a different string. Every language's translation of
   `‘{}’ repository by` is discarded for this credit, and the English still
   renders correctly, which is exactly the failure mode `translation-parity`
   warns reads as fine until someone checks.

2. **Missing content**: upstream builds its About dialog with
   `Adw.AboutDialog.new_from_appdata(metainfo_path, VERSION)`
   (`main.py:167-169`), which populates the dialog's `comments` (the one-line
   app summary shown under the title/version — metainfo's `<summary>`,
   `Compress videos to target sizes`) and reads the long `<description>`
   paragraphs for the dialog's "Details" view. The port's `about_dialog`
   (`application.rb:203-226`) builds `Adwaita::AboutDialog.new` field by field
   and never sets `comments` or any description text — there is no metainfo
   file in the port for it to read, at all (see `component-identification.md`
   row 20/21). The About dialog a user opens in the port is missing its own
   one-line summary.

**Verdict: gap**, on the text axis for (1) and on presence for (2).

## Unit: desktop launcher entry — `data/*.desktop.in`

No port counterpart exists (`.reports/component-identification.md` row 21).
**Verdict: gap.** `GenericName=Video Compressor`, `Comment=Compress videos to
target sizes`, `Keywords=Compress;Video;Movie;Film;Clip;`, and the
`New Window` desktop action are all upstream strings a packaged port should
expose to the shell's launcher/search, and none of them exist anywhere in the
port.

## Units not exercised by anything that drives them: `progress_pie.rb`, `progress_popover_box.rb`, `attempt_fail_box.rb`, `drag_overlay.rb`

Static reading shows these four files build the right widget trees (see
`component-identification.md`), and the widget-count axis is clean. But
`test/drive_constrict.rb` — the only thing in this port that actually runs
any of it — never instantiates `Constrict::ProgressPie`,
`Constrict::ProgressPopoverBox`, `Constrict::AttemptFailBox` or
`Constrict::DragOverlay` by name (grep confirms zero hits across
`test/*.rb` — re-confirmed this round against the now-188-check suite, same
zero hits). That is a 188/188 pass that covers roughly 14 of this port's ~18
component classes and says nothing — not even that the file loads — about
the other four. The 38 checks added this round exercise `SourcesRow`'s real
glycin decode path and fix a harness bug (see `test-parity.md`); neither
touches any of these four files. See `test-parity.md` and
`accountability-ensurance.md`: this is the "component no check exercises is
unverified, not done" case the task asked to be treated as a gap in its own
right, and it is **not reflected anywhere in the drive output's "188 of 188
/ DRIVE OK" headline**, which is exactly the false-green shape this review
exists to catch.

## Summary

| Unit | Verdict |
|---|---|
| Application (actions, accelerators) | parity |
| Main window (widgets/actions/behaviour) | parity |
| About dialog content (text) | **gap** — reworded msgid + missing summary/description |
| Desktop launcher entry | **gap** — no port file at all |
| Source row | widget/behaviour axis: parity; **text axis: regression this round** — 3 msgids at `sources_row.rb:390,411,558-561` were byte-identical to upstream (`U+202F`) and were rewritten to a plain space in `a69438d`, on the strength of a previous report's wrong claim — see `translation-parity.md`'s corrected Gap 1 and `accountability-ensurance.md`'s top entry |
| Sources list box | parity (not re-derived in detail here; scan clean) |
| Preferences dialog | parity (scan clean) |
| Error dialog | parity (scan clean) |
| Shortcuts dialog | parity — table-driven, C_() context verified byte-identical (see translation-parity.md) |
| Progress pie / progress popover box / attempt-fail box / drag overlay | widget tree present, **unverified** — nothing in the port's own test suite ever builds or drives one |
