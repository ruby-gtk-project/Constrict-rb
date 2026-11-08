# Test parity — Constrict

| | |
|---|---|
| Upstream | `main` @ `ecd8b7d` |
| Port | `ruby` @ `4ba7d7a` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test command | `nix develop --command xvfb-run -a ruby test/drive_constrict.rb` |

Upstream has no test suite: `test-census.sh` against the upstream worktree
returns zero rows, and there is no `test/`/`tests/` directory, no
`unittest`/`pytest` import, and no test target in `meson.build`. **Parity is
0/0 and is met trivially — the port inherits no safety net from upstream.**
Verified by re-running the census script in this session
(`.claude/skills/test-parity/scripts/test-census.sh /tmp/up` → 0 rows).

## Extra

- `test/drive_constrict.rb` — 188 checks, run and confirmed green in this
  session (`188 of 188 checks passed`, `DRIVE OK`). Drives everything the
  150-check version did (window construction, both pages, the breakpoint,
  the primary menu, sidebar toggling, the sources list box
  (locking/reordering), a source row's own menu and suffix buttons, the
  preferences/error/shortcuts/about/cancel-confirmation dialogs, the
  application's and window's actions and accelerators, opening/focusing/
  closing multiple windows, `Settings`, `Enums`, `Style`, the CLI option
  parser and i18n), plus two steps added this round: a real glycin
  image-decode path (`sources_row.rb#texture_from_file` fed an actual 1x1
  PNG and a deliberately corrupt one, asserting both the successful decode
  and the generic-icon fallback) and a fix to a harness bug — the original
  file called `app.quit` mid-script, which tears down the GLib main loop
  the driver's own `pump`/`schedule` runs on, so every step registered
  after it (12 steps, including the final empty-again check) silently
  never ran. `app.quit` is now the very last step, with its own check
  folded in before returning.
- `test/drive_window.rb` — superseded by the above per its own header
  comment (older, unasserted, kept for reference).

**This suite was actually executed, not assumed** — re-run in this session
under `nix develop --command xvfb-run -a ruby test/drive_constrict.rb` and
confirmed the exact `188 of 188 checks passed` / `DRIVE OK` this round's gate
describes. The `.reports/spec-suite-gap.md` note about the separate
`kettle-jem` RSpec scaffold (`spec/`) failing to load (`kettle-test` gem not
vendored in the Nix dev shell) is accurate and does not affect this suite —
`spec/` has zero `*_spec.rb` files regardless, so there is no test content
blocked by that gap, only an empty scaffold directory that cannot even
report "0 examples" cleanly.

## The gap this ledger's bijection cannot see: coverage inside the 188

A 0/0 upstream bijection and a green 188/188 port run both read as "done."
Reading what the 188 checks actually touch shows they are **not an
even sample of the port's own component list**, and the task's own "33
components" figure does not correspond to anything counted inside this
repository (`grep -i component test/*.rb` returns nothing) — this report
does not vouch for that number:

- **Four component classes are never instantiated by name anywhere in
  `test/*.rb`**: `Constrict::ProgressPie`, `Constrict::ProgressPopoverBox`,
  `Constrict::AttemptFailBox`, `Constrict::DragOverlay` (confirmed:
  `grep -n "ProgressPie\|ProgressPopoverBox\|AttemptFailBox\|DragOverlay"
  test/*.rb` returns nothing — re-confirmed this round, unchanged by the
  38 checks added since last round). These are real, non-trivial widgets —
  a Cairo drawing-area subclass, a popover body, a failed-attempt summary
  box, and the drag-and-drop reveal overlay used on both pages — and none
  of their code has ever run under test. The new glycin-decode checks added
  this round exercise `SourcesRow#texture_from_file` directly, not any of
  these four.
- **The core feature — an actual successful compression** — is explicitly
  never driven, per `test/drive_constrict.rb`'s own header: "this machine's
  dev shell ships no `ffprobe`, `ffmpeg`, `gst-video-thumbnailer` or `vainfo`
  ... so every staged video in this run is probed, fails, and goes BROKEN
  ... the success path (an actual two-pass compress) cannot be driven here."
  That means `CurrentAttemptBox`'s live-progress rendering, `AttemptFailBox`'s
  retry summary, and `ProgressPie`'s drawn arc are all on a path the harness
  cannot reach even in principle on this machine, not just a path nobody
  happened to call.
- **`Gtk::FileDialog` is not driven by clicking**, per the same header — the
  file-open and export-folder pickers are exercised, if at all, only through
  whatever code paths don't require the portal.

None of this is recorded anywhere as a limitation of the "188 of 188 / DRIVE
OK" number itself — the drive script's own header comment states the
`ffmpeg`-dependent gap and labels it "Out of scope, and why" (see
`accountability-ensurance.md` — that labeling, however accurate the
underlying unavailability of `ffmpeg` in this sandbox is, is the excuse
pattern that skill exists to catch: it is written calmly, as a scoping
decision, in the file whose output this round's gate quotes as the proof the
port works).

**Verdict**: test parity with upstream is 0/0, trivially met. The port's own
188-check suite is real and was executed in this session, not assumed, and
grew genuinely (a real decode path, a real harness bug fixed) since last
round. But it still exercises roughly 14 of the port's ~18 widget-owning
classes (see `component-parity.md`'s summary table) — adding checks to
existing classes does not change that count — and the task's framing
applies directly here: a component no check exercises is unverified, not
done. The headline "188 of 188, DRIVE OK" (or the task's own "33
components") should not be read as "the port is proven," only as "the ~14
component classes this harness reaches are proven, with more checks per
class than before."
