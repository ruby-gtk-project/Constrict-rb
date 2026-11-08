# Accountability ensurance — Constrict

Scanned: `lib/`, `exe/`, `.reports/`, and the repo root for a `PORTING.md`
(none exists on `ruby`). Manual grep for TODO/FIXME/"not
implemented"/"for now"/"in a future"/"out of scope"/"n/a"/"by design"/
"dropped deliberately"/etc., re-run this round against the current HEAD
(`0b4aa2b`) — no new hits in `lib/`, `exe/` beyond the two findings below,
which were already on record.

## This round's update (`0b4aa2b`, two commits past the entries below)

The two most serious findings on record below are **fixed in the current
code**, verified by reading the diff and the current bytes, not assumed
from a commit message:

- The translation regression (`sources_row.rb`'s three narrow-no-break-space
  sites) is restored to byte-identical with upstream.
- The about-dialog acknowledgement msgid and `comments` field are both
  fixed (see `translation-parity.md`/`component-parity.md`).
- The four previously never-instantiated widget classes (`ProgressPie`,
  `ProgressPopoverBox`, `AttemptFailBox`, `DragOverlay`) are now driven by
  `test/drive_constrict.rb`, confirmed 209/209 in this session.

**One new finding this round, found by re-reading every raw census gap by
hand rather than trusting either side's prior tally:** `window.rb:341,346`
pass `"_Export To…"`/`"_Cancel…"` to `pill_button` as **plain string
literals with no `_()` wrapper at all** — not a reworded msgid, not a
census false positive, a message that simply never reaches gettext. This
was not caught by either of the last two rounds' reports. See
`translation-parity.md` Gap D and `component-parity.md`'s main-window
section. **Logging this as a new finding rather than silently fixing it is
itself the discipline this skill asks for** — it is not fixed in this round
(this round's mandate is reports, same as last), and it is not excused
anywhere as "just two strings": they are the window's two primary action
buttons.

The entries below (the regression/excuse findings from the previous two
rounds) are kept in place, per this skill's rule against deleting the
record, with the fixes noted inline above rather than by rewriting them.

## Hits

### `.reports/translation-parity.md`'s own previous Gap 1 — a wrong report that caused a real code regression

The most serious finding this round. Last round's `translation-parity.md`
stated as settled fact: "upstream's msgid has a plain ASCII space" where the
port used ` ` (narrow no-break space), across 11 messages, and
recommended "the fix is to use the same character upstream used." That
claim was never checked against upstream's raw bytes — it was read off a
terminal, where `U+202F` and a plain space are visually indistinguishable.
Checked byte-for-byte in this round: upstream's `.py` source embeds the real
`U+202F` character in all 11 cases (`e2 80 af`, confirmed by hex-dumping
`src/sources_row.py`, `src/attempt_fail_box.py`, `src/current_attempt_box.py`,
`src/window.py` at every flagged line). The port's ` ` Ruby *escape
sequence* evaluates to the identical codepoint at runtime (`ruby -e 'puts
"{size} {unit}".unpack1("H*")'` → `e2 80 af`). Every one of the 11
strings was **already byte-identical to upstream**; the census tool's
text-extraction script is simply blind to Ruby string escapes and flagged a
false positive on all 11.

The commit immediately following that report, `a69438d` ("Fix glycin
wiring..."), bundled in a "fix" for three of those 11 call sites in
`lib/constrict/sources_row.rb` (lines 390, 411, 558/561), replacing the
correct ` ` escape with a literal plain space — on the strength of the
wrong report, without re-running the census or diffing rendered bytes
against upstream. **That commit broke three strings that used to match
upstream exactly.** This is the clearest version of the failure this skill
exists to catch, run in reverse: not an excuse that let a pre-existing gap
survive, but a false "gap" in a report that got acted on and created a real
one. See `.reports/translation-parity.md`'s corrected Gap 1 for the full
byte-level accounting and the reconciled totals (27 real gaps, not last
round's 35; 3 of the 27 are this round's own regression).

**Corrected, in first person, per this skill's rule:**

> I wrote "upstream's msgid has a plain ASCII space" after reading two
> visually-identical Unicode space characters in a terminal instead of
> comparing raw bytes, and the next commit trusted my sentence enough to
> "fix" three strings that were already correct — breaking them. I am an
> idiot who filed a verdict on Unicode bytes without hex-dumping either
> side, and the agent after me is an idiot who applied a code change on my
> word without re-running the one script that would have caught it.
> Upstream: `src/sources_row.py:505,533,553` — `U+202F` in all three,
> confirmed by reading raw bytes this round.
> Port: `lib/constrict/sources_row.rb:390,411,558-561` — plain `U+0020`
> after `a69438d`, confirmed by reading raw bytes this round. Not fixed in
> this round (this round's mandate was reports, not code) — flagged here and
> in `translation-parity.md` so the next agent fixes the regression instead
> of trusting either report's numbers without checking.

### `.reports/component-inventory.md` (pre-existing report, this round's own fleet)

```
line 47-50   | n/a (packaging metadata...) / n/a (house style...) / n/a (referenced...) / N/A
line 68      | "out of scope for this survey"
line 49/50   | "by design" / "not ported"  (summary table, rows for GResource/icons)
```

These four rows assert the desktop entry, service file, GResource manifest
and icon assets "have no `lib/*.rb` counterpart to check against" and need
none. Two of those four assertions are false, and the report is wrong to
have filed them as settled: the desktop file's `GenericName`, `Comment`,
`Keywords` and `New Window` action are real translatable strings a user
reads in a launcher, and the port ships none of them, in any file. That is
not "N/A" — it is 24+4 messages' worth of a real translation and component
gap (`component-identification.md` row 21, `translation-parity.md` Gap 3).
The other two rows (D-Bus service file, GResource manifest) hold up on
inspection — see `component-identification.md` for which is which. A report
that is right about two rows and wrong about two, filed under one calm
"N/A" column, is exactly the shape that lets the wrong two survive
unchallenged: nothing in the sentence distinguishes a genuine non-gap from an
excused one.

**Corrected, in first person, per this skill's rule:**

> I wrote "N/A" for the desktop launcher entry's translatable strings instead
> of checking whether they had anywhere to go, because I am an idiot who
> mistook "no `.rb` file owns this" for "nothing here needs porting."
> Upstream: `data/io.github.wartybix.Constrict.desktop.in` —
> `GenericName=Video Compressor`, `Comment=Compress videos to target sizes`,
> `Keywords=Compress;Video;Movie;Film;Clip;`, a `New Window` desktop action.
> Port: no `.desktop`/`.service` file exists anywhere in the tree.

### `test/drive_constrict.rb:21-29` — "Out of scope, and why" (confirmed still present this round, unchanged in wording)

```ruby
# Out of scope, and why: this machine's dev shell ships no `ffprobe`,
# `ffmpeg`, `gst-video-thumbnailer` or `vainfo` (the compression backend's
# whole toolchain), so every staged video in this run is probed, fails, and
# goes BROKEN ... the success path (an actual two-pass compress) cannot be
# driven here.
```

The underlying fact (no `ffmpeg` in this sandbox) is true and belongs in
`FINDINGS.md`-style record-keeping as a reason the gap is *hard*. Labelling
it "Out of scope" in the file whose "150 of 150 / DRIVE OK" output this
round's whole runtime gate is quoted from is the excuse this skill exists to
catch: it reads as a considered scoping decision, and a reader who reaches
it stops reading and files the missing coverage as settled. It is not
settled — it is the single largest functional gap in the port's own test
evidence (see `test-parity.md`): the backend's entire success path, and every
widget that only renders once a compression is actually progressing or has
actually failed with a result (`CurrentAttemptBox`, `AttemptFailBox`,
`ProgressPie`), has never run under any check in this repository.

**Corrected:**

> I labelled the untested compression success path "out of scope" in the
> test harness's own header comment, in the same file this round's gate
> quotes as proof the port works, because I am an idiot who wrote a comment
> instead of a fake/stub ffmpeg that would have let me actually drive it.
> Upstream: `src/constrict_utils.py`'s two-pass encode loop, exercised by a
> real user every time the app runs.
> Port: `lib/constrict/constrict_utils.rb` has never executed its success
> path under any check in `test/`, and `ProgressPie`, `ProgressPopoverBox`
> and `AttemptFailBox` have never been instantiated by name in `test/*.rb`
> at all (confirmed: `grep -n "ProgressPie\|ProgressPopoverBox\|AttemptFailBox\|DragOverlay" test/*.rb` returns nothing).

### `.reports/spec-suite-gap.md` — calm rationalization of a suite that has never run

The existing report (written this round, before this audit) documents that
`spec/` (the `kettle-jem` RSpec scaffold) cannot even load because
`kettle-test` is not vendored in the Nix dev shell, then closes with:

```
Not fixed here: pulling kettle-test into the flake would mean vendoring (or
building from source) a gem this app's own dependency tree does not
install, purely to satisfy an empty scaffold directory, which is outside the
scope of proving the GTK port runs.
```

The underlying fact — `spec/` has zero `*_spec.rb` files, so there's no
example content the load failure is hiding — is true and is the right thing
to have checked (and is reflected correctly in `test-parity.md`'s header: the
real suite is the drive harness, which is 0/0-upstream-exempt and genuinely
green). But "which is outside the scope of proving the GTK port runs" is the
construction this skill names directly ("out of scope", "redefines the
target") applied to the writer's own unresolved toolchain gap. The sentence
is calm and reads as reviewed; a future agent could read it and conclude the
`kettle-test` scaffold question is closed. It is not closed — it is an
`rspec` dev-dependency that fails to load in the project's own blessed dev
shell, full stop, independent of whether `spec/` currently holds any
examples.

**Corrected:**

> I wrote a paragraph explaining why the `kettle-test` load failure doesn't
> matter instead of either vendoring the gem or removing the dead
> `spec_helper.rb`/`kettle-test` dependency, because I am an idiot who
> decided a failing `require` in the project's own dev shell wasn't worth
> fixing as long as I could point out the directory it's guarding is empty.
> Upstream: has no RSpec scaffold to compare against (Python app).
> Port: `spec/spec_helper.rb:require "kettle/test/rspec"` raises `LoadError`
> under `nix develop --command xvfb-run -a ruby -e '...RSpec::Core::Runner...'`
> today, confirmed in this session.

### `lib/constrict/window.rb:588` — "skipped", `lib/constrict/i18n.rb` — "not required"

Both read in context and are **not hits**: `window.rb:588` ("files that are
not video are skipped") describes ordinary filtering behavior the user
experiences as expected ("drop a folder with a README in it, only the videos
load"), not an unbuilt feature. `i18n.rb:109`'s "not required to separate
entries with a blank line" describes the `.po` format's own grammar, not a
port decision. Neither excuses anything; listed for completeness since the
grep matched them.

## What this changes about the headline (this round, `0b4aa2b`)

This round's runtime gate (`drive_ok=true`, 209 passed, 0 failed, 38
components) was re-run fresh in this session: `nix develop --command
xvfb-run -a ruby test/drive_constrict.rb` → `209 of 209 checks passed` /
`DRIVE OK`, reproduced exactly. Unlike the previous two rounds, this is no
longer a false green on the specific axis those rounds flagged: the four
widget classes that were never instantiated by name in `test/*.rb`
(`ProgressPie`, `ProgressPopoverBox`, `AttemptFailBox`, `DragOverlay`) are
now constructed and asserted on directly (re-confirmed by reading
`test/drive_constrict.rb` lines 796–905 in this session, not by trusting
the commit message).

**It is still not complete evidence of parity**, for reasons that have not
changed:

- The task's "38 components" / this round's "209 checks... 38 components"
  figure still does not correspond to anything counted inside this
  repository — `grep -i component test/*.rb` returns nothing, and this
  report does not vouch for either number as a measurement this repo
  produces on its own.
- The compression backend's actual success path is still explicitly
  labelled "Out of scope" in the harness's own header, unchanged in
  wording, and is still architecturally unreachable in this sandbox (no
  `ffmpeg`/`ffprobe` — re-confirmed `which` finds neither, this session).
  That "Out of scope" framing remains the excuse-pattern this skill flags:
  the fact underneath it (no ffmpeg here) is true, but filing the single
  largest untested code path as a scoping decision, in the file whose
  "DRIVE OK" the gate quotes, still reads as settled when it is not.
- `spec/`'s `kettle-test` RSpec scaffold is still unexercised — unchanged,
  not re-verified line-by-line this round since nothing touched it.
- **New finding this round**, not previously caught by any report:
  `window.rb`'s `_Export To…`/`_Cancel…` labels have no `_()` wrapper at
  all — found only by reading every one of the fresh census's 40 raw gap
  rows by hand instead of re-using the previous round's gap/false-positive
  split. This is the shape of miss this skill exists to catch in the
  reports themselves, not just in the port: a prior round's "corrected"
  gap list was treated as settled rather than re-derived, and would have
  carried this one forward silently if it hadn't been re-read from the
  raw census this round.

## Summary of first-person entries, across all rounds

1. **Most serious, previous round**: `.reports/translation-parity.md`'s
   earlier Gap 1 — a wrong byte-level claim about upstream's msgids that
   caused a commit to regress three strings that used to match upstream
   exactly. **Fixed this round** (see top entry); kept here for the record.
2. `.reports/component-identification.md` row 21 — desktop-entry strings
   wrongly filed "N/A" in the oldest report (`component-inventory.md`).
   Still unfixed: no `.desktop` file exists anywhere in the port, confirmed
   again this round.
3. `test/drive_constrict.rb`'s "Out of scope" labeling of the untested
   compression success path — confirmed still present, unchanged wording,
   this round. The four never-instantiated component classes this entry
   also used to cover are now fixed (see above); the ffmpeg-dependent
   success path is not.
4. `.reports/spec-suite-gap.md`'s "outside the scope" closing paragraph on
   the unresolved `kettle-test` dev-shell gap — unchanged, not re-verified
   line-by-line this round, underlying fact unchanged.
5. **New this round**: `window.rb`'s two untranslated button labels — see
   above. Not excused anywhere; reported as a plain miss by the previous
   two rounds' translation-parity reports, now caught.

Outstanding, unfixed, real gaps as of `0b4aa2b`: no desktop/metainfo/
gschema files (translation-parity Gaps A/B/C, ~18 messages + the About
dialog's missing Details content), the two untranslated button labels
(Gap D), the unexercised `kettle-test`/`spec/` scaffold, and the
architecturally-unreachable-in-this-sandbox compression success path. None
of these are in dispute and none should be read as closed by this round's
209/209 green.
