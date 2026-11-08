# Test parity — Constrict

| | |
|---|---|
| Upstream | `main` @ `ecd8b7d` |
| Port | `ruby` @ `0b4aa2b` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test command | `nix develop --command xvfb-run -a ruby test/drive_constrict.rb` |

Upstream has no test suite: no `test/`/`tests/` directory, no
`unittest`/`pytest` import anywhere in `src/`, no test target in
`meson.build` (re-confirmed this round: `git ls-tree -r --name-only
origin/main | grep -iE 'test|spec'` returns nothing). **Parity is 0/0 and
is met trivially — the port inherits no safety net from upstream.**

## The port's own suite — re-run this session, not assumed

`test/drive_constrict.rb` was executed fresh in this session:

```
nix develop --command xvfb-run -a ruby test/drive_constrict.rb
...
209 of 209 checks passed
DRIVE OK
```

This matches the runtime gate this round (`drive_ok=true`, 209 passed, 0
failed) exactly — confirmed by actually running it, not by trusting the
gate's own report of itself.

### What changed since the last report (filed against `4ba7d7a`, two commits
back)

The previous round's test-parity report flagged that `Constrict::ProgressPie`,
`Constrict::ProgressPopoverBox`, `Constrict::AttemptFailBox` and
`Constrict::DragOverlay` were never instantiated by name anywhere in
`test/*.rb` — a real, class-level gap in coverage, independent of the
188/188 headline at the time. **This is fixed in the current file.** Four
new steps (re-read in this session, `test/drive_constrict.rb` lines
796–905) construct each class directly and assert on real behaviour:

- `ProgressPie` — `fraction=` round-trips, drawing at 0%/partial/full all
  leave the widget realised (not crashed), one screenshot taken.
- `AttemptFailBox` — an overshoot case and an undershoot case, asserting
  the attempt number and the failure-detail text both read correctly.
- `ProgressPopoverBox` — assembles a top widget plus a failed attempt,
  asserts the tracked failure and the assembled announcement string, and
  that `set_top_widget` swaps correctly.
- `DragOverlay` — child delegation past the `Adwaita::Bin` override, the
  drop target, and that the hint starts hidden.

That accounts for 21 of the 21 new checks (188 → 209) beyond general
suite growth; grep confirms all four class names now appear in
`test/drive_constrict.rb` where the previous round found zero hits.

## What is still not driven, and is not a trivial gap

The harness's own header comment (`test/drive_constrict.rb:21-29`, unchanged
in wording this round) states plainly: this sandbox's dev shell ships no
`ffprobe`, `ffmpeg`, `gst-video-thumbnailer` or `vainfo`. Re-confirmed this
session:

```
$ nix develop --command bash -c "which ffmpeg ffprobe gst-video-thumbnailer vainfo"
which: no ffmpeg in (...)
```

(exit 4, nothing found). That means:

- **The compression backend's actual success path** — `constrict_utils.rb`'s
  two-pass encode loop — has never executed under any check in this
  repository, in this environment, full stop. Every staged video in the
  drive run is probed, fails, and goes BROKEN by design; the success path
  is architecturally unreachable here, not just untested by omission.
- **`CurrentAttemptBox`'s live-progress rendering** during an actual
  running attempt is not exercised — the class is now instantiated (in the
  `ProgressPopoverBox` step and in `SourcesRow`), but only in its
  constructed/idle state, never while a real attempt is updating it.
- **`Gtk::FileDialog`** is still not driven by clicking (async, backed by a
  portal this display has none of); the code behind its call sites is
  driven directly instead, per the harness's own documented workaround.

None of this is new, and none of it is fixed this round. The harness's
own "Out of scope, and why" framing for the ffmpeg gap is itself flagged as
an excuse-pattern in `accountability-ensurance.md` — the underlying fact
(no ffmpeg in this sandbox) is true, but labelling the single largest
untested code path "out of scope" in the same file whose "DRIVE OK" output
the runtime gate quotes is the shape this audit exists to catch.

## No RSpec suite exists or runs

`spec/` holds only `spec_helper.rb` and a `README.md` — zero `*_spec.rb`
files. `spec_helper.rb` requires `kettle/test/rspec`:

```
$ nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; ...'
```

was not re-run this session against the `spec/` directory specifically
(there is nothing in it to run), but the dev shell banner's own spec
command (`ruby -e 'require "rspec/core"; exit
RSpec::Core::Runner.run(...)'`) depends on `spec_helper.rb` loading
successfully, and `kettle-test` is not vendored in this Nix flake's gem set
(confirmed: `.reports/spec-suite-gap.md`, not re-verified line-by-line this
round since the underlying fact — no `*_spec.rb` files exist regardless —
has not changed and no commit touched `spec/`, `Gemfile`, or `flake.nix`
since the last check). **This scaffold has still never been exercised, in
any round.** Call it an open, unresolved gap, not a closed question: a
future `bundle add kettle-test` (or a Gemfile/flake fix) could still fail
to load, and nobody has checked since.

## Verdict

Test parity with upstream is 0/0, trivially met — upstream ships no tests
to be behind on. The port's own 209-check drive suite is real, was executed
in this session, and genuinely grew this round by closing the specific
class-level gap (`ProgressPie`/`ProgressPopoverBox`/`AttemptFailBox`/
`DragOverlay` never instantiated) the previous round correctly identified.
What remains unverified is not a component class any more — it is a
code *path*: the real two-pass compression success path, which this
sandbox cannot drive at all, and the unexercised `spec/` RSpec scaffold.
"209 of 209, DRIVE OK" should be read as "every component class the
harness can reach in this sandbox is now driven," not as "the compression
backend works" — that claim has no check behind it anywhere in this
repository.
