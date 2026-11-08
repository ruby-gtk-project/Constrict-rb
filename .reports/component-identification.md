# Component identification — Constrict

| | |
|---|---|
| Upstream | `main` @ `ecd8b7d` |
| Port | `ruby` @ `4ba7d7a` |

This supersedes `.reports/component-inventory.md`'s verdict on rows 21–24. That
file is kept (history), but its "N/A" / "by design" rows for the metainfo,
desktop and gschema files are wrong: those files are not packaging trivia,
they are **translatable-string sources that feed real on-screen text**
(`Adw.AboutDialog.new_from_appdata` reads the metainfo directly; the desktop
file's `Name`/`Comment`/`Keywords` are what a user sees in a launcher; the
gschema `<summary>`/`<description>` are what `dconf-editor` shows). Calling
them "N/A" is the exact excuse pattern `accountability-ensurance` exists to
catch — see that report. Below is the corrected unit list.

## Units (one `lib/constrict/*.rb` each, in the order a user meets them)

| # | Upstream file(s) | Port file | Owner of |
|---|---|---|---|
| 1 | `src/main.py` | `lib/constrict/application.rb` | app actions, accelerators, About dialog |
| 2 | `src/window.blp` + `src/window.py` | `lib/constrict/window.rb` | main window: status page, queue page, breakpoint, dialogs it owns (cancel-confirm) |
| 3 | `src/drag_overlay.blp` + `.py` | `lib/constrict/drag_overlay.rb` | drag-and-drop reveal overlay |
| 4 | `src/sources_list_box.blp` + `.py` | `lib/constrict/sources_list_box.rb` | staged-video list |
| 5 | `src/sources_row.blp` + `.py` | `lib/constrict/sources_row.rb` | one source row |
| 6 | `src/progress_pie.py` | `lib/constrict/progress_pie.rb` | Cairo circular progress indicator |
| 7 | `src/progress_popover_box.blp` + `.py` | `lib/constrict/progress_popover_box.rb` | attempt-history popover body |
| 8 | `src/current_attempt_box.blp` + `.py` | `lib/constrict/current_attempt_box.rb` | one attempt's live progress |
| 9 | `src/attempt_fail_box.blp` + `.py` | `lib/constrict/attempt_fail_box.rb` | one failed attempt's summary |
| 10 | `src/error_dialog.blp` + `.py` | `lib/constrict/error_dialog.rb` | error-detail dialog |
| 11 | `src/preferences_dialog.blp` + `.py` | `lib/constrict/preferences_dialog.rb` | preferences dialog |
| 12 | `src/gtk/shortcuts-dialog.blp` | `lib/constrict/shortcuts_dialog.rb` | shortcuts dialog |
| 13 | `src/enums.py` | `lib/constrict/enums.rb` | shared enums |
| 14 | `src/shared.py` | `lib/constrict/shared.rb` | cross-thread UI helper |
| 15 | `src/constrict_utils.py` | `lib/constrict/constrict_utils.rb` | compression backend |
| 16 | `src/constrict_cli.py` | `lib/constrict/cli.rb` | CLI entry point |
| 17 | `data/*.gschema.xml.in` | `lib/constrict/settings.rb` | GSettings schema |
| 18 | `src/gtk/style.css` | `lib/constrict/style.rb` | stylesheet |
| 19 | `po/*`, every `_()`/`ngettext()`/`C_()` call site | `lib/constrict/i18n.rb` | translation catalogue + markers |
| 20 | `data/*.metainfo.xml.in` + about-dialog fields in `main.py` | `lib/constrict/application.rb` (`about_dialog`) | About-dialog content, **including the app summary/description metainfo supplies that the port's manually-built dialog never sets — see `component-parity.md`** |
| 21 | `data/*.desktop.in` | **no port file** | launcher entry: `Name`, `GenericName`("Video Compressor"), `Comment`, `Keywords`, the `New Window` desktop action. The port ships no `.desktop`/`.service` file at all — this is a real gap, not packaging trivia, because three of its four translatable fields are strings a user reads in a shell/activities launcher |
| 22 | `data/*.service.in` | **no port file** | D-Bus activation — infrastructure, no translatable text, genuinely has no widget/string counterpart |
| 23 | `src/constrict.gresource.xml.in` | n/a | upstream build-time artifact binding `.ui`→GResource; the port's house style builds widgets in Ruby directly, which is the one correspondence in this list that actually holds (no string or behaviour is lost by skipping a resource-compilation step) |
| 24 | `data/icons/**/*.svg` | n/a | icon assets referenced by name; no translatable text |

Rows 21 (desktop file) and 20 (metainfo content never surfaced) are real
gaps, written up in `component-parity.md` and `translation-parity.md`. Rows
22–24 are the only ones where "no counterpart needed" is actually true.

## Scan baseline (component-scan.sh, read as a lead only — see component-parity.md for the reconciled, read-the-file verdict)

| | Upstream rows | Port rows |
|---|---:|---:|
| `component-scan.sh` output | 177 | 149 |

Full per-unit widget/CSS/signal/action reconciliation is in
`component-parity.md`; most of the raw scan delta turns out to be shared
Ruby-side factory methods (`menu_button`, `pill_button`, `help_button`,
`osd_progress_bar`, `check_row`, `grouped_check_button` in `window.rb`) that
the textual scan counts once per method body instead of once per call site —
a correspondence once you read the call sites, not a gap. The two deltas that
survive reading are in `component-parity.md`.
