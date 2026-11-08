# Accountability ensurance — Constrict

Scanned: `lib/`, `exe/`, `.reports/`, and the repo root for a `PORTING.md`
(none exists on `ruby`). `find-excuses.sh` plus a manual grep for
TODO/FIXME/"not implemented"/"for now"/"in a future"/"out of scope"/"n/a"/
"by design"/"dropped deliberately"/etc.

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

## What this changes about the headline

This round's runtime gate (`drive_ok=true`, 188/188, 33-component claim) was
re-run in this session (`nix develop --command xvfb-run -a ruby
test/drive_constrict.rb` → `188 of 188 checks passed` / `DRIVE OK`,
reproduced exactly). The suite grew from the previous round's 150 checks by
adding a real glycin image-decode test (`write_fake_png`) and fixing a real
harness bug (`app.quit` tore down the main loop the remaining steps ran on,
so 12 later steps silently never executed — see the commit
`4ba7d7a`/the file's own section-9/11 comments). Both are genuine
improvements, confirmed by reading the diff and re-running the suite, not
assumed.

It is still not, on its own, evidence of parity. The "33 components" figure
in the task's own framing does not correspond to anything counted inside
this repository — `grep -i component test/*.rb` returns nothing — and this
report does not vouch for it. What the suite's own `grep` confirms,
unchanged from last round: `Constrict::ProgressPie`, `::ProgressPopoverBox`,
`::AttemptFailBox` and `::DragOverlay` are still never instantiated by name
anywhere in `test/*.rb`, and the compression backend's success path is still
explicitly "Out of scope" per the file's own header. Reporting the 188/188
gate as "clean" without this report and `test-parity.md`/`component-parity.md`
would be the false green this task asked to be hunted for.

## Summary of first-person entries this round added

1. **New, most serious**: `.reports/translation-parity.md`'s previous Gap 1
   — a wrong byte-level claim about upstream's msgids that caused the very
   next commit (`a69438d`) to regress three strings that used to match
   upstream exactly. See the top entry above.
2. `.reports/component-identification.md` row 21 — desktop-entry strings
   wrongly filed "N/A" (carried over from last round, confirmed still
   accurate this round, upstream unchanged).
3. `test/drive_constrict.rb`'s "Out of scope" labeling of the untested
   compression success path and the four never-instantiated component
   classes (confirmed still present, unchanged wording, this round).
4. `.reports/spec-suite-gap.md`'s "outside the scope" closing paragraph on
   the unresolved `kettle-test` dev-shell gap (confirmed still unresolved —
   `require "kettle/test/rspec"` still raises `LoadError` in this session).

None of the underlying technical facts (desktop file absent, no `ffmpeg` in
this sandbox, `kettle-test` not vendored, the four never-instantiated widget
classes) is in dispute, and none has been fixed since last round. What was
wrong last round is that each was written in a register that reads as a
decision rather than a debt, or — in the new, worse case — was simply wrong
about the underlying bytes and got acted on. They are rewritten above; the
original documents are left in place per this skill's rule against deleting
the excuse.
