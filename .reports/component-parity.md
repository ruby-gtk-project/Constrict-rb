# Component parity — Constrict

| | |
|---|---|
| Upstream | `main` @ `ecd8b7d` |
| Port | `ruby` @ `0b4aa2b` |
| Units with full parity | 11 / 16 widget units; 1 app-level unit (desktop launcher) carries a confirmed presence gap; main window carries a newly found text-axis gap (two untranslated button labels); the previous round's source-row text regression is fixed |

**This round's changes, verified against current source, not assumed:**
the `sources_row.rb` narrow-space regression is fixed (restored to
byte-identical with upstream); the about-dialog msgid rewording is fixed
and its `comments` field is now set; `ProgressPie`, `ProgressPopoverBox`,
`AttemptFailBox` and `DragOverlay` are now instantiated and asserted on by
`test/drive_constrict.rb` (confirmed: 209/209 checks pass, all four appear
by name in the drive script with real assertions, not placeholder calls —
re-run in this session). A new gap was found this round that no previous
round reported: `window.rb`'s `_Export To…`/`_Cancel…` button labels have
no `_()` wrapper at all. See `translation-parity.md` Gap D for the full
detail; summarized under the main-window unit below.

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

**Verdict: parity** on the widget/behaviour axes, once the scan's
factory/false-positive noise is read through. This unit does not deserve
the raw scan's apparent 10-widget gap.

**New this round — text axis, real gap:** `open_button`/`clear_all_button`
pass through fine, but `export_button` and `cancel_button`
(`window.rb:341,346`) call `pill_button("_Export To…", "win.export")` and
`pill_button("_Cancel…", "win.cancel")` with **plain string literals, no
`_()` wrapper**. `pill_button` (window.rb:735-745) assigns `button.label =
label` verbatim — nothing downstream translates it either. Upstream wraps
both (`src/window.blp:347,363`: `label: _("_Export To…");` /
`label: _("_Cancel…");`). These are the window's two primary action
buttons — not a rare path — and they will render in English in every
non-English locale. See `translation-parity.md` Gap D.

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

**Both gaps this report previously filed here are now fixed, verified
against current source:**

1. **Acknowledgement msgid — fixed.** `application.rb:36` now holds the
   template key `"‘{}’ repository by"`, and the call site
   (`interpolate(_(title), "8mb")`, `application.rb:222`) substitutes
   `"8mb"` **after** translation, matching upstream's
   `_('‘{}’ repository by').format('8mb')` exactly, same order.
2. **`comments` field — fixed.** `application.rb:210` sets `dialog.comments
   = _("Compress videos to target sizes")`, byte-identical to upstream's
   metainfo `<summary>`.

**Still a gap, narrower than before:** upstream's
`Adw.AboutDialog.new_from_appdata` also reads the metainfo's long
`<description>` paragraphs and the "Features include:" bullet list for the
dialog's "Details" view. The port's `about_dialog` sets no equivalent
text anywhere — there is still no `data/*.metainfo.xml.in` (or hand-built
replacement) to read from. A user who opens the About dialog and clicks
through to Details sees nothing where upstream shows four feature bullets
and a two-paragraph description. See `translation-parity.md` Gap A for the
12 messages this costs.

**Verdict: the two previously-filed gaps are fixed; the deeper gap (no
Details content at all) remains and was always a subset of "Gap 3"/"Gap
A" rather than a separate finding.**

## Unit: desktop launcher entry — `data/*.desktop.in`

No port counterpart exists (`.reports/component-identification.md` row 21).
**Verdict: gap.** `GenericName=Video Compressor`, `Comment=Compress videos to
target sizes`, `Keywords=Compress;Video;Movie;Film;Clip;`, and the
`New Window` desktop action are all upstream strings a packaged port should
expose to the shell's launcher/search, and none of them exist anywhere in the
port.

## Units previously unexercised, now driven: `progress_pie.rb`, `progress_popover_box.rb`, `attempt_fail_box.rb`, `drag_overlay.rb`

**Fixed this round.** The previous round's report found that
`test/drive_constrict.rb` never instantiated any of these four classes by
name. The current `test/drive_constrict.rb` (re-read this session) adds
four real steps that construct and assert on each one directly:
`Constrict::ProgressPie.new` (fraction updates, drawing at 0%/partial/full
all leave the widget realised, screenshotted), `Constrict::AttemptFailBox`
(overshoot and undershoot cases, label content asserted),
`Constrict::ProgressPopoverBox` (top-widget assembly, failure tracking,
announcement string), `Constrict::DragOverlay` (child delegation, drop
target, hint visibility). Re-run in this session:
`nix develop --command xvfb-run -a ruby test/drive_constrict.rb` →
**209 of 209 checks passed, DRIVE OK**, with the four widgets' sections
([33]–[36]) all `ok`. This closes the specific "component no check
exercises" gap previously filed here for these four classes.

**What is still not driven, by the harness's own header comment (unchanged
this round):** an actual successful two-pass compression (`ffmpeg`/
`ffprobe` absent from this sandbox — confirmed again this session, `which
ffmpeg ffprobe` finds neither in the Nix dev shell), so `CurrentAttemptBox`'s
live-progress rendering and the real backend success path have still never
executed under any check, in this environment, even though their owning
widget classes are now instantiated synthetically. See `test-parity.md`.

## Summary

| Unit | Verdict |
|---|---|
| Application (actions, accelerators) | parity |
| Main window (widgets/actions/behaviour) | widget/behaviour axes: parity; **text axis: gap (new this round)** — `_Export To…`/`_Cancel…` button labels have no `_()` wrapper |
| About dialog content (text) | previous round's two gaps (reworded msgid, missing `comments`) **fixed this round**; still missing the Details-view description/feature-bullet text (subset of the metainfo gap) |
| Desktop launcher entry | **gap** — no port file at all (unchanged) |
| Source row | widget/behaviour axis: parity; **text axis: regression fixed this round** — the 3 msgids at `sources_row.rb:390,411,558-561` are restored to byte-identical with upstream |
| Sources list box | parity (scan clean) |
| Preferences dialog | parity (scan clean) |
| Error dialog | parity (scan clean) |
| Shortcuts dialog | parity — table-driven, C_() context verified byte-identical (see translation-parity.md) |
| Progress pie / progress popover box / attempt-fail box / drag overlay | widget tree present, **now driven and asserted** by `test/drive_constrict.rb` (209/209, confirmed this round) — the real backend success path (ffmpeg absent from this sandbox) remains the one thing none of these can be driven through |
