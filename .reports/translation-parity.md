# Translation parity — Constrict

| | |
|---|---|
| Upstream | `main` @ `ecd8b7d` (unchanged this round) |
| Port | `ruby` @ `4ba7d7a` |
| Domain | upstream: `constrict` (from `po/meson.build`) — port: **not emitted** (no `.mo`/domain concept; `domain_matches: false`) |
| Upstream messages | 138 (165 occurrences, 14 reused, 6 plural, 9 with context) |
| Ported (raw census) | 94 |
| Gaps (raw census) | 44 — **27 real, see corrected walkthrough below (this round corrects the previous round's own Gap 1, which was itself wrong — see "Correction" below)** |
| Extra (untranslated) | 11 — **3 real** |
| Upstream languages | 30 `.po` files, 4,016 translated, 113 untranslated, 1 fuzzy |
| Languages shipped by the port | 30/30 — `po/` copied verbatim, `LINGUAS` matches |
| Unresolved markers (port) | 4 (the `C_("shortcut window", title/label)` calls over the `SECTIONS` table in `lib/constrict/shortcuts_dialog.rb` — see below) |

Numbers from `catalogue.rb --compare`, regenerated in this session over
`origin/main` and the current `ruby` tip; raw TSVs/YAMLs are reproducible
with the `translation-parity` skill's scripts.

## Correction to the previous round's Gap 1 — and the regression it caused

The previous round's report (committed at `01ae768`) claimed: "Twelve call
sites across four files insert ` ` (narrow no-break space) between a
placeholder and its unit, where upstream's msgid has a plain ASCII space,"
and filed this as an 11-message gap recommending the fix "use the same
character upstream used."

**That claim is backwards, and checking it byte-for-byte (not by eyeballing
a terminal, where U+202F and a plain space render almost identically) shows
why:**

```
$ python3 -c "print(repr(open('src/sources_row.py',encoding='utf-8').read()[...]))" 
"Target size ({size} {unit}) is too low for this file."
```

Upstream's own `.py` source files embed the real U+202F character in all
eleven of these msgids (confirmed by reading the raw bytes of
`src/attempt_fail_box.py`, `src/current_attempt_box.py`, `src/window.py`
and `src/sources_row.py` at every flagged line — every one is `e2 80 af`,
not `0x20`). The port's `lib/constrict/*.rb` files wrote the *Ruby escape
sequence* ` ` (six source characters: backslash, u, 2, 0, 2, F) inside
a double-quoted string literal, which Ruby's own lexer evaluates to the
identical `U+202F` codepoint at runtime —

```
$ ruby -e 'puts "{size} {unit}".unpack1("H*")'
7b73697a657de280af7b756e69747d   # ...e2 80 af... = U+202F, byte-identical to upstream
```

— so at runtime, before this round, every one of these 11 strings rendered
to the user **byte-identical to upstream**. This was never a translation
gap. It was a blind spot in `msgid-census.sh`'s text extraction: the script
reads `.rb` source with a regex over raw bytes and never evaluates Ruby
string-escape sequences, so a literal ` ` escape and a literal `U+202F`
character look different to the script and identical to every actual
reader, translator and `.po` lookup at runtime. Reading the upstream `.py`
side of the same comparison has the opposite problem in reverse — Python's
source embeds the raw codepoint directly, so the census parses it correctly
there, which is exactly what made the two sides look mismatched: one side's
extraction was escape-blind, the other wasn't, and nobody checked why before
writing "upstream has a plain ASCII space" as settled fact.

**The actual damage: that false report caused a real regression.** The very
next commit after the reports were filed (`a69438d`, this round, titled "Fix
glycin wiring...") also rewrote three of the eleven call sites in
`lib/constrict/sources_row.rb` (lines 390, 411, 558/561) from the
escape-sequence ` ` to a literal plain space, following the previous
report's "fix" recommendation. That commit did not re-run the census or
diff the rendered bytes against upstream before calling it fixed — it took
the wrong report's word for it. The result: those three strings, which
matched upstream exactly before this round, are now wrong. This is a **real,
newly introduced gap**, not a pre-existing one, and it is the opposite
direction from what last round's report described.

**Corrected, in first person, per the accountability-ensurance rule:**

> I wrote "upstream's msgid has a plain ASCII space" by reading a terminal
> rendering of two visually-indistinguishable Unicode space characters
> instead of comparing raw bytes, and told the next commit to "fix" code
> that was already byte-identical to upstream. That commit took my word for
> it and did not check either, and now three strings that used to match
> upstream no longer do.
> Upstream: `src/sources_row.py:505,553,533` — `U+202F` (narrow no-break
> space) in all three, confirmed by reading the raw UTF-8 bytes.
> Port: `lib/constrict/sources_row.rb:390,411,558-561` — plain `U+0020`
> space after the `a69438d` commit, confirmed by reading the raw bytes of
> the current file. Fix: restore ` ` at these three sites; do not trust
> a text-scraping census over a Ruby file without accounting for escape
> sequences.

## Gap 1, corrected: only 3 of the 11 are real, and they are new

| File:line | Upstream (`U+202F`?) | Port, current (`U+202F`?) | Verdict |
|---|---|---|---|
| `attempt_fail_box.rb:133` | yes | yes (` ` escape, unchanged) | **parity** — census false positive |
| `attempt_fail_box.rb:135` | yes | yes (unchanged) | **parity** — census false positive |
| `attempt_fail_box.rb:146` | yes | yes (unchanged) | **parity** — census false positive |
| `current_attempt_box.rb:140` | yes | yes (unchanged) | **parity** — census false positive |
| `current_attempt_box.rb:168` | yes | yes (unchanged) | **parity** — census false positive |
| `window.rb:403` | yes | yes (unchanged) | **parity** — census false positive |
| `window.rb:474` | yes | yes (unchanged) | **parity** — census false positive |
| `window.rb:512` | yes | yes (unchanged) | **parity** — census false positive |
| `sources_row.rb:390` | yes | **no — plain space, regressed in `a69438d`** | **real gap, newly introduced this round** |
| `sources_row.rb:411` | yes | **no — plain space, regressed in `a69438d`** | **real gap, newly introduced this round** |
| `sources_row.rb:558,561` | yes | **no — plain space, regressed in `a69438d`** | **real gap, newly introduced this round** |

Net effect on the catalogue's raw numbers: 8 of the 11 raw `gap`+`extra`
pairs the census reports here are tooling false positives (parity, not
gaps). The 3 `sources_row.rb` pairs are real — and are regressions, not
carryover.

## The one real pass: po/ itself

The port copied upstream's whole `po/` directory unchanged (30 files, matches
`LINGUAS`), and `lib/constrict/i18n.rb` is a from-scratch `.po` parser +
plural-rule evaluator that reads it at runtime (no `gettext`/`fast_gettext`
gem dependency — correctly handles fuzzy/obsolete exclusion, the `Plural-Forms`
header, and multi-form plurals). This is real, working infrastructure, not a
checkbox. The catalogue it loads at runtime was verified in the drive run
(`ok the licence is GPL-3.0`, etc., all strings resolved through `_()`
without raising).

## Gap 1 (systemic, 11 messages): a narrow no-break space inserted into the msgid

Twelve call sites across four files insert ` ` (narrow no-break space)
between a placeholder and its unit, where upstream's msgid has a plain ASCII
space:

| File:line | Port msgid (owed bytes differ) | Upstream msgid |
|---|---|---|
| `attempt_fail_box.rb:133` | `Compressed file size was too large ({size} {unit})` | `Compressed file size was too large ({size} {unit})` |
| `attempt_fail_box.rb:135` | `Compressed file size was too small ({size} {unit})` | `Compressed file size was too small ({size} {unit})` |
| `attempt_fail_box.rb:146` | `{vid_br} {vid_br_unit} ({extra_details})` | `{vid_br} {vid_br_unit} ({extra_details})` |
| `current_attempt_box.rb:140` | `Compressing to {vid_br} {vid_br_unit} ({extra_details})` | `Compressing to {vid_br} {vid_br_unit} ({extra_details})` |
| `current_attempt_box.rb:168` | `{} %` | `{} %` |
| `window.rb:403` | `{} FPS` | `{} FPS` |
| `window.rb:474` | `Videos compressed to low bitrates may be capped to {} FPS, regardless of the option set.` | `...{} FPS, regardless...` |
| `window.rb:512` | `...A tolerance of {} % or more is recommended.` | `...A tolerance of {} % or more is recommended.` |
| `sources_row.rb:390` | `Video compressed to {size} {unit}.` | `Video compressed to {size} {unit}.` |
| `sources_row.rb:411` | `Target size ({size} {unit}) is too low for this file.` | `Target size ({size} {unit}) is too low for this file.` |
| `sources_row.rb:558,561` | `Video file size ({original_size} {unit_original}) already meets the target size ({target_size} {unit_target}).` | plain spaces |

Each row is **two gaps at once**: the upstream key is a `gap` (missing from
the port's catalogue lookups) and the port's rewritten key is `extra`
(untranslated in all 30 languages, because nobody has ever translated a
string with ` ` in it). 30 languages × 11 messages is the concrete cost:
every one of those strings, which upstream's translators already did, now
shows in English in the port, in every locale, forever, until the bytes
match. This is not a cosmetic choice recorded anywhere in the port's source —
there is no comment at any of these sites explaining the substitution; it
reads as an unannounced, systemic rewording. **Gap.** Never reword upstream's
msgid to "improve" it; the fix is to use the same character upstream used, in
all twelve places, which closes 11 gaps and removes 11 extras in one pass.

## Gap 2 (real, text axis): the about-dialog credit heading

Upstream's msgid is the template `‘{}’ repository by` (`main.py:186`,
substituted with `'8mb'` via `.format()` *after* translation). The port
(`application.rb:37`) bakes the substitution into the key itself:
`"‘8mb’ repository by"`. Different msgid; 30 languages' translation of the
template is discarded. **Gap** — also recorded in `component-parity.md`
against the About-dialog unit.

## Gap 3 (real, missing files, ~24 messages): metainfo / desktop / gschema strings

The port ships no `data/` directory at all — no `.metainfo.xml.in`, no
`.desktop.in`, no `.gschema.xml.in` of its own (the GSettings schema is
reimplemented directly in `lib/constrict/settings.rb`, with no
`<summary>`/`<description>` strings carried across). The 24 messages these
three file types hold upstream — the app's long description paragraphs, the
feature-list bullets ("Bulk compression of multiple videos...", "Automatic
calculation of average bitrate..."), the desktop entry's `GenericName`,
`Comment`, `Keywords`, `New Window` action label, and the two gschema
`<summary>` strings for codec/framerate — have nowhere in the port to land.
**Gap**, 24 messages, all of category "missing" rather than "reworded." One
concrete, user-visible consequence is already in `component-parity.md`: the
About dialog the port shows is missing the one-line app summary upstream's
`new_from_appdata` call pulls from exactly this file.

## The 9 that look like gaps and are not: shortcuts-dialog context strings

`lib/constrict/shortcuts_dialog.rb` builds its `C_("shortcut window", ...)`
calls from a `SECTIONS` table (`title`/`label` are loop variables, not
literals), so the automated census cannot resolve them — they show up as 4 of
the port's `unresolved: 4` and the comparison reports all 9 as `gap`. Hand
census (required by the skill whenever `unresolved` is non-zero) against
`src/gtk/shortcuts-dialog.blp` shows every title and item label byte-identical,
under the same `"shortcut window"` context, in the same two sections (Video
Management: Open, Export; General: Toggle Settings Pane, Show Shortcuts,
Close Window, Quit, Show Preferences). **Ported**, not a gap — corrected count
below.

## Reconciled totals

| | Raw census | Corrected |
|---|---:|---:|
| Ported | 94 | 94 + 9 (shortcuts) + 8 (Gap-1 census false positives, see above) = **111** |
| Gaps | 44 | 44 − 9 (shortcuts) − 8 (Gap-1 false positives) = **27** |
| Extra | 11 | 11 − 8 (Gap-1 false positives) = **3** (the `sources_row.rb` regression, real — see above) |

`summary.parity` is `false` and stays `false`: 27 real gaps — down from the
previous round's wrongly-counted 35, but 3 of these 27 are a **regression
this round introduced** (see the Gap-1 correction above), not inherited
debt: `sources_row.rb:390,411,558-561` used to match upstream byte-for-byte
and no longer do. Also `domain_matches` false (the port has no
`.mo`/gettext domain at all — a real, separate finding: there is no
`msgfmt -c` validation and no C plural-forms engine in the loop,
`lib/constrict/i18n.rb`'s own instead, which is adequate but is not "the
domain matches"). This was not evaluated against a running non-English
locale beyond what the drive harness already exercises in English; a
`LANGUAGE=de` headless run asserting on one translated string was **not run
in this session** — name it as an unrun check rather than a silent pass.

## What is unchanged from last round and still real

- **Gap 2** (about-dialog credit heading, reworded msgid) — confirmed still
  present at `application.rb:37`, upstream unchanged at `ecd8b7d`.
- **Gap 3** (~24 messages: no `.metainfo.xml.in`/`.desktop.in`/
  `.gschema.xml.in` in the port) — confirmed no `data/` directory exists on
  `ruby`.
- The shortcuts-dialog `C_()` false-gap resolution (9 messages) — unchanged,
  still correctly "ported."
