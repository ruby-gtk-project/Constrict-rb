# Accountability ensurance — Constrict

Scanned: `lib/`, `exe/`, `.reports/`, and the repo root for a `PORTING.md`
(none exists on `ruby`). `find-excuses.sh` plus a manual grep for
TODO/FIXME/"not implemented"/"for now"/"in a future"/"out of scope"/"n/a"/
"by design"/"dropped deliberately"/etc.

## Hits

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

### `test/drive_constrict.rb:21-29` — "Out of scope, and why"

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

The task's runtime gate (`drive_ok=true`, 150/150, 14 components) is real —
it was re-run in this session and reproduced exactly. It is not, on its own,
evidence that the port has parity: it is a true statement about 14 of this
port's ~18 component classes, running a path that by the harness's own
header comment excludes the backend's success case. Reporting that gate as
"clean" without the three write-ups above would be the false green this task
asked to be hunted for.

## Summary of first-person entries this round added

1. `.reports/component-identification.md` row 21 — desktop-entry strings
   wrongly filed "N/A".
2. `test/drive_constrict.rb`'s "Out of scope" labeling of the untested
   compression success path and the four never-instantiated component
   classes.
3. `.reports/spec-suite-gap.md`'s "outside the scope" closing paragraph on
   the unresolved `kettle-test` dev-shell gap.

None of the three underlying technical facts (desktop file absent, no
`ffmpeg` in this sandbox, `kettle-test` not vendored) is in dispute. What is
wrong is that each was written in a register that reads as a decision
rather than a debt. They are rewritten above; the original documents are
left in place per this skill's rule against deleting the excuse.
