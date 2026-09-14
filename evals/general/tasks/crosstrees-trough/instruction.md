# tmux: variation-selector-widened characters vanish in offset panes

This is a debugging task against the real upstream tmux source tree. You are
given a user-visible symptom and a tree that still contains the defect. You
must reproduce the symptom yourself with a script you write, repair the tree,
and prove both.

## Environment

- `/app/src` is a working copy of the real tmux tree: a depth-1 git clone
  checked out at commit `936bb6e7cdff4fc7700a4f36a6b828b87d9f8241`, fully
  editable (owned by your uid) and already built -- `/app/src/tmux` is the
  compiled binary. The clone keeps its git metadata (one commit, no history),
  and `.git` must stay intact.
- Toolchain installed: gcc, make, autotools, bison, byacc, libevent, libncurses
  and libutempter dev packages, plus the locale `C.UTF-8`. If you change source
  files, rebuild with `cd /app/src && make -j1` from the repo root. You should
  not need to re-run `./autogen.sh`/`./configure` unless you change build files.
- The tree ships its own self-contained regression-test scripts under
  `/app/src/regress/`. Each is a plain `sh` script that starts its own tmux
  test servers and prints a failure and exits non-zero on any mismatch; run any
  of them as e.g.
  `cd /app/src/regress && TEST_TMUX=$PWD/../tmux sh ./name-of-script.sh`.
  You may use these scripts to understand expected behaviour and to validate a
  fix, and the verifier will run some of them against your final tree.
- THERE IS NO NETWORK in this container. Nothing can be fetched at trial time;
  any tmux server you start runs locally, so give each one its own socket with
  `-L <name>` and no config with `-f /dev/null`. Never let a test talk to your
  real session's tmux.
- One setting matters for the symptom: the server option
  `variation-selector-always-wide` (set with
  `tmux set -s variation-selector-always-wide on`), which makes tmux always
  treat characters followed by a variation selector as double-width.

## Symptom (what a user reports)

With `variation-selector-always-wide` enabled, an emoji character whose display
width a variation selector widens (the glyph is followed by U+FE0F / "VS16")
gets **dropped entirely** -- rendered as an empty cell -- whenever it is drawn
inside a pane that begins at a nonzero horizontal offset, the classic case
being the right-hand side of a horizontal window split. The application writes
the character, but the pane shows a blank where it should be, so text looks
like it has holes in it even though the character is well within the pane's
visible area. The missing glyph does not come back on redraw. The same
character in the pane at offset 0 (e.g. the left half of the split), or on the
very first line of the offset pane, displays fine -- which is why the defect is
easy to miss in quick tests.

## Task

1. First write a failing reproduction, the deliverable `/app/repro.sh`: an
   executable, self-contained shell script which, run as `sh /app/repro.sh`,
   drives the built `/app/src/tmux` to exhibit the symptom and exits non-zero
   (printing what it observed) **while the defect is present**. It must be
   deterministic, use only local sockets under `/tmp`, and finish in under a
   minute. Do this before touching the source; run it and keep its failure
   output.
2. Localise and repair the defect in `/app/src` so the symptom is gone and
   `/app/repro.sh` exits 0.
3. Make sure nothing else broke: the project's own regression scripts under
   `/app/src/regress/` that exercise the affected drawing paths must still
   pass, and your repro must still pass after the rebuild.
4. Leave the tree in its fixed state (source changes in place, `.git` intact)
   with `/app/repro.sh` at `/app/repro.sh`.

## Grading contract

- Deliverable: `/app/repro.sh`. It must pass (`exit 0`) when run against the
  repaired build on the same image.
- The verifier rebuilds the tree in two states: the pristine checked-out state
  and the state you left it in. It requires your repro to **fail** on the
  pristine (defect-present) build and **pass** on yours; it runs the project's
  own regression test for this drawing path and requires it to pass on your
  build; it additionally checks the fixed build renders such characters
  correctly in several geometries (different panes, pane offsets and glyphs,
  including pane offsets in both axes); and it runs a few more of the
  project's own regression scripts from `regress/` to show the fix broke
  nothing else.
- Do not modify anything under `/opt/golden` or `/tests`. Do not delete
  `/app/src`, its `.git`, or the build files; a tree that cannot be rebuilt
  cleanly cannot earn the reward.