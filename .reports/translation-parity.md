# Translation parity — Constrict

| | |
|---|---|
| Upstream | `main` @ `ecd8b7d` (unchanged this round) |
| Port | `ruby` @ `0b4aa2b` |
| Domain | upstream: `constrict` (from `po/meson.build`) — port: **not emitted** (no `.mo`/domain concept; `domain_matches: false`) |
| Upstream messages | 138 (165 occurrences, 14 reused, 6 plural, 9 with context) |
| Port raw census | 106 messages, 122 occurrences, `unresolved: 4` |
| Raw census gaps / extra | 40 gap, 8 extra |
| **Corrected gaps / extra** (after reading every row by hand — see below) | **20 real gaps, 0 real extra** |
| Upstream languages | 30 `.po` files, 4,016 translated, 113 untranslated, 1 fuzzy |
| Languages shipped by the port | 30/30 — `po/` copied verbatim, `LINGUAS` matches |

Regenerated fresh this session: `catalogue.rb --role upstream` over
`origin/main`, `catalogue.rb --role port` over the current `ruby` tip,
`catalogue.rb --compare` over both. Full YAML is reproducible with the
`translation-parity` skill's scripts; every one of the 40 raw gaps and 8 raw
extras below was read against the actual source on both sides, not taken
from the census number.

## This round's fixes (commit `0b4aa2b`, confirmed by reading current source)

Two real gaps carried from the previous round are fixed:

1. **`sources_row.rb:390,411,558/561` narrow-space regression — fixed.**
   Restored to the ` ` escape, matching upstream's `U+202F` at
   `src/sources_row.py:505,533,553` byte-for-byte. (This also removes 3 of
   the previous round's 8 "extra" rows, all of which were a tooling
   artifact anyway — see below.)
2. **About-dialog acknowledgement msgid — fixed.** `application.rb`'s
   `ACKNOWLEDGEMENTS` key is now the template `"‘{}’ repository by"`
   substituted with `interpolate(_(title), "8mb")` **after** translation,
   matching upstream's `_('‘{}’ repository by').format('8mb')` exactly.
3. **About-dialog `comments` — now set.** `dialog.comments = _("Compress
   videos to target sizes")` matches upstream's metainfo `<summary>`
   word-for-word. The long `<description>` paragraphs are still not
   carried (see Gap A below) but the one-line summary is.

## Reading the 40 raw gaps: 20 are census tooling artifacts, 20 are real

The census extracts a msgid only from a literal `_("...")`/`C_(...)`
call. Three independent patterns make a real, byte-identical translation
look like a gap to the script without being one:

**(a) Multi-line `\`-continued Ruby string literals (8 rows).** Both sides
hold the identical final string once Ruby concatenates the continuation —
confirmed by reading the assembled literal against the upstream single-line
`.py` string for every row:

`attempt_fail_box.rb:133,135,146`, `current_attempt_box.rb:140,168`,
`window.rb:403,474,512` — all byte-identical to upstream once the `\`
continuations are read as one string. **Not gaps.**

**(b) A msgid baked into a variable used across multiple
`add_acknowledgement_section` calls (3 rows).** `application.rb`'s
`ACKNOWLEDGEMENTS` hash keys `"Circular progress indicator design by"` and
`"Drag overlay design by"` (plus the already-covered `"‘{}’ repository
by"`) are translated via `_(title)` inside an `.each` loop — the census
only recognizes a literal argument to `_()`, not a hash key translated
three lines later. Read against `src/main.py:186,194,199`: byte-identical.
**Not gaps.**

**(c) `C_("shortcut window", ...)` built from a loop table (9 rows).**
`shortcuts_dialog.rb`'s `SECTIONS` table supplies `title`/`label` as loop
variables, not literals, so the census cannot resolve 4 of them (hence
`unresolved: 4`) and reports all 9 section/item titles as `gap`. Read
against `src/gtk/shortcuts-dialog.blp`: every title and label is
byte-identical, same context, same two sections (Video Management: Open,
Export; General: Toggle Settings Pane, Show Shortcuts, Close Window, Quit,
Show Preferences). **Not gaps.**

That accounts for 8 + 3 + 9 = 20 of the 40 raw gaps, and separately for all
8 raw extras (the port's assembled/`_(title)`-translated versions of the
same 11 strings in (a) and (b), which the census also lists as "extra"
because it cannot match them back to anything). **Real extra count: 0.**

## The 20 real gaps

| Group | Messages | Where |
|---|---:|---|
| **Gap A — metainfo content** | 12 | `data/io.github.wartybix.Constrict.metainfo.xml.in` doesn't exist in the port: the `<description>` paragraphs, "Features include:" and its four bullet points, two screenshot captions ("Source videos queued for compression", "The application mid-compression"). None of these have anywhere to land without a metainfo file (or an equivalent hand-built string table) in the port. |
| **Gap B — desktop entry** | 3 | `data/io.github.wartybix.Constrict.desktop.in` doesn't exist: `GenericName=Video Compressor`, `Comment`/`Keywords=Compress;Video;Movie;Film;Clip;`, and the `New Window` desktop action label. No `.desktop` file ships at all. |
| **Gap C — gschema summaries** | 3 | `data/io.github.wartybix.Constrict.gschema.xml.in` doesn't exist: the `<summary>` text for the codec key ("The codec used to encode with during compression", "Video Codec") and the framerate-limit key ("Limits framerates of compressed videos automatically, or to 30 FPS or 60 FPS."). `lib/constrict/settings.rb` reimplements the schema's behaviour but carries none of its translatable summary text. |
| **Gap D — untranslated button labels (newly found this round)** | 2 | `lib/constrict/window.rb:341,346`: `pill_button("_Export To…", "win.export")` and `pill_button("_Cancel…", "win.cancel")` pass plain Ruby string literals straight to `button.label=` with **no `_()` wrapper at all** — confirmed by reading `pill_button`'s definition (`window.rb:735-745`), which just assigns `label` verbatim. Upstream wraps both: `src/window.blp:347` `label: _("_Export To…");`, `:363` `label: _("_Cancel…");`. These two strings will show in English in every non-English locale, in the window's primary action buttons — not an edge case, the two buttons a user clicks most. **This is a real, previously unreported gap.** |

12 + 3 + 3 + 2 = 20.

## domain_matches: false — still open, unevaluated at runtime beyond English

The port emits no `.mo`/gettext domain; `lib/constrict/i18n.rb` is a
from-scratch `.po` parser + plural evaluator run at runtime instead, which
is real working infrastructure (verified live in the drive run — every
`_()` call resolves without raising). But no non-English locale was
exercised in this session: a `LANGUAGE=de` (or similar) headless run
asserting on one translated string was **not run**. Name it as an unrun
check, not a silent pass — the catalogue loading without raising in English
says nothing about whether a `.po` file's plural forms or placeholder
substitution actually come out right for a translated locale.

## What's unchanged from last round and still real

- Gap A/B/C above (previously filed as "Gap 3", ~24 messages for metainfo +
  desktop + gschema) — same underlying absence of a `data/` directory,
  recount above is the first time each file type's messages were separated
  and totalled precisely (12+3+3 = 18, not the previous round's blended
  "~24").
- `domain_matches: false` and the unrun non-English locale check.

## New this round

- Gap D (`_Export To…`/`_Cancel…` missing `_()` wrapper) — not identified
  in any previous round's report. Found by reading every raw census gap
  by hand rather than trusting the tooling's own false-positive/true-gap
  split from last round.
- The previous round's narrow-no-break-space regression and the
  acknowledgement-msgid gap are both fixed and verified byte-identical to
  upstream.
