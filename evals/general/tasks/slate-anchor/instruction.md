# slate-anchor — headless build of the legacy plotsmith

The legacy **plotsmith** grid plotter lives at `/app/plotsmith` (read the
`docs/BUILDING.txt` inside the tree for the shipped build lore). The tree is
configured for the old way of doing things: a plain `./configure` defaults to
`--with-x`, which compiles the X11 frontend `gui/xfront.c`, links the X11
library shim under `compat/`, and produces the windowed binary
`plotsmith-x`. This host has **no X11 stack and no display**, so that is not
an acceptable deliverable.

Your job: produce the **non-graphical engine** — configured without the X11
path — and run it. Work only inside `/app`. Do not modify anything under
`/app/plotsmith/` or `/app/jobs/` (the verifier re-checks them
byte-for-byte; configuration is done by running `./configure`, not by
editing).

## Deliverables (all required, exact paths)

1. `/app/plotsmith/plotsmith` — the headless engine binary, produced by:
   ```
   cd /app/plotsmith && ./configure --without-x && make
   ```
   Requirements checked by the grader:
   * the binary exists and runs;
   * it references **no** X11 library: no `X11` entry of any kind in its
     dynamic section, and none of the `XOpenDisplay`-family symbols from the
     X path present in its symbol table;
   * the X frontend object (`gui/xfront.o`-style code) is not linked in.
2. `/app/plotsmith/config.mk` — the configure-generated file from the
   `--without-x` run (it must select the headless configuration).
3. `/app/out-map.pbm` — the output of actually running the headless binary on
   the visible job:
   ```
   /app/plotsmith/plotsmith /app/jobs/visible-job.txt /app/out-map.pbm
   ```

## Engine contract (re-checked on hidden jobs)

`plotsmith <job.txt> <out.pbm>` applies the job to the built-in 24x16
1-bit-per-pixel canvas and writes plain ASCII PBM (`P1`): header `P1`, then
`24 16`, then 16 rows of 24 tokens `0`/`1` (0 = paper, 1 = ink)
space-separated. Job-file semantics (as implemented in `core/`):

* verbs: `dot X Y`, `hline X1 X2 Y`, `vline X Y1 Y2`, `rect X Y W H`
  (outline; rows `Y`/`Y+H-1` and cols `X`/`X+W-1`; `W,H` must be `> 0`),
  `fill X Y W H` (solid; `W,H` `> 0`), `clear`;
* blank lines and lines whose first token starts with `#` are skipped; a
  line with an unknown verb, wrong argument count, or non-integer arguments
  is skipped without error;
* every primitive clips: pixels outside the canvas are ignored;
  `hline`/`vline` accept endpoints in either order and are inclusive.

## What the grader verifies (summary)

* byte-for-byte integrity of `/app/plotsmith/` and `/app/jobs/`;
* `/app/plotsmith/plotsmith` is an executable with zero X11 linkage;
* a fresh `./configure --without-x && make` in a clean copy of the tree
  rebuilds the headless binary;
* the delivered binary and a freshly rebuilt one both reproduce the expected
  PBM byte-for-byte on hidden job files (clipping edges, dense overlaps,
  malformed lines, mid-job `clear`);
* `/app/out-map.pbm` matches a re-run of the binary on the visible job.

There is no network access at any point.
