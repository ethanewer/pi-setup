# Modernise a 1997 C codebase onto a 2024 toolchain

## Situation

`/app/src` is a shallow, pinned clone of the upstream repository
`id-Software/DOOM` (commit `a77dfb96cb91780ca334d0d4cfd86957558007e0`,
cloned with `--depth 1`). The interesting part for this task is the
`linuxdoom-1.10/` subdirectory: the original 1997 Linux port of DOOM, one of
the first released id Software source releases. It is **pristine upstream
bytes**; nothing in it has been altered or intentionally broken.

The build environment is modern and does not match the era of the code:

- gcc 13 (Ubuntu 24.04), glibc 2.39, a 64-bit userspace, and X11 development
  headers are installed.
- Xvfb is installed so the X11 game binary can run headlessly.
- There is **no network** at trial time. Everything you need is in the image.
- The machine is pinned to 1 CPU. Full builds of this tree take seconds, not
  minutes; budget your iterations accordingly.

As shipped, `/app/src` **does not build**. The compile/link failures are the
real, unseeded incompatibilities between 1997 C and the 2024 toolchain -
obsolete headers that glibc dropped, a symbol clash with the current libc,
initialisers the modern compiler refuses, and 64-bit assumptions that did not
exist in 1997. This is a debugging task: read the errors, understand the
causes, and repair the source (or the project's own build script) so the
project builds and runs again. Do not paraphrase the project, stub out its
subsystems, or replace code with lookalikes; the verification runs the
project's own binary and its own demo machinery.

## What is on disk and what is installed

- `/app/src/linuxdoom-1.10/` - the source tree you must repair.
- `/app/genwad.py` - an authored generator (Python 3, stdlib only) that
  writes a minimal but structurally valid DOOM IWAD (`doom1.wad`) plus a
  recorded demo file. Usage: `python3 /app/genwad.py <outdir> <gametics> <demo-name>`.
- `/app/fixtures/` - a pre-generated fixture: `doom1.wad` + `d1.lmp`
  (a 100-tic recorded demo) + `params.env`. Regenerate with `/app/genwad.py`
  if you like; the numbers are what matter.
- `/app/run_demo.sh` - a helper that builds the tree (forwarding any make
  arguments) and plays a fixture demo headlessly. See its header comment.
- Compiler toolchain: `gcc`, `make`, glibc headers, X11 headers, `xvfb-run`.
  Nothing else needs installing.

Do not modify `/app/genwad.py`, `/app/run_demo.sh`, or `/app/fixtures/`; they
are harness tools. Change only the cloned tree.

## Output contract

Repair `/app/src/linuxdoom-1.10/` so that all of the following hold:

1. **It builds from clean with the stock build script.** From
   `/app/src/linuxdoom-1.10`:
   ```
   rm -rf linux && make
   ```
   must succeed and produce `linux/linuxxdoom`. Do not change the compiler
   flags the project's own build script uses. (You may need to change the
   build script itself for a different reason - see item 4 - but never to
   weaken warning/error checking.)

2. **It also builds with other flag sets.** The verification rebuilds the
   tree with different optimisation and warning flags (not just the
   project's defaults, and never with `-Werror`). Your repair must be
   robust to `-O2` and to the unoptimised `-g` configuration, not just to
   one configuration. A repair that only silences the default build is
   considered a fail.

3. **The produced binary plays the recorded demo headlessly and reports the
   timing it was built for.** Run the binary the way the helper does:
   ```
   cd /app/fixtures
   DOOMWADDIR=/app/fixtures xvfb-run -a -s "-screen 0 320x200x8" \
     /app/src/linuxdoom-1.10/linux/linuxxdoom -timedemo d1 -nodraw -noblit
   ```
   The game boots, loads the IWAD, enters the recorded level, plays every
   tic of the demo, and stops at the demo terminator by reporting, on
   stderr:
   ```
   Error: timed <N> gametics in <M> realtics
   ```
   where `<N>` equals the number of gametics the demo fixture was generated
   with (100 for `/app/fixtures/d1.lmp`). The process then exits with code
   255; that exit code is the game's normal self-report and is expected. The
   timing line is the meaningful output. The verifier re-generates fixtures
   with other gametic counts and expects the matching number in the timing
   line, so the demo must genuinely play through, not print a hardcoded
   string.

4. **The repair is a modernisation, not a bypass.** Resolve each
   incompatibility at its root: fix the code that is wrong, stop the build
   from referencing things the toolchain no longer provides, and keep the
   game's own subsystems intact. Do not weaken the compiler flags, disable
   the game's subsystems (video, sound, networking), add global
   `-fpermissive`-style hacks, `#if 0` large regions, or otherwise rig the
   build to pass. The verifier rebuilds from the clean tree with multiple
   flag sets and runs the real binary; any of those shortcuts either fails
   to build, fails to boot, or fails to play the demo.

## Hints (not answers)

- Run `make` early and read the *full* error list; the first error is only
  the first roadblock. Errors will also appear at the link stage and only
  when the binary actually starts up. The build log and the run output are
  the oracle; they tell you what the toolchain objects to, in its own words.
- The runtime behaviour under `-O2` can differ from the default build; an
  optimisation-visible defect is still your defect to fix.
- `linux/` is the object/binary output directory; the project expects you to
  create it (`mkdir -p linux`).

## Evaluation

The verifier, for each of several build configurations (the project's
default flags, an optimised set, and an unoptimised set) and for each of
several demo fixtures with distinct gametic counts, will:

- wipe and recompile `/app/src/linuxdoom-1.10` from scratch with that
  configuration's flags;
- run the freshly built binary against a freshly generated fixture;
- require the `Timeout timed <N> gametics` self-report with the fixture's
  exact `<N>`.

It scores 1 only if every configuration builds and every fixture reports its
exact gametic count.

Start by building. Good luck.