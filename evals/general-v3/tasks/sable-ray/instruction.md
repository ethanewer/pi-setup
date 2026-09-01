# Reverse-engineer the compiled terrain sunlight pass

`/app/target/raycaster` is a compiled C program you did **not** receive the
source for. It performs one rendering/scene operation on a terrain heightmap
and prints a result. Your job is to determine **exactly** which operation it
performs — by running it on probe grids you construct, by disassembling it
(`objdump -d /app/target/raycaster`; binutils is installed), under `gdb`, or
any combination — and then reimplement it in pure Python.

## Environment

- Working directory: `/app`. It already contains the probe fixture
  `/app/scene/grid.txt` and the target binary `/app/target/raycaster`.
  Python 3.12 and binutils/gdb are available.
- **`/app/target/raycaster` is a protected fixture.** Its bytes are checked at
  verification time. Do **not** modify, replace, rename, or delete it.
- `/app/scene/grid.txt` is a supplied example; do not modify it.
- Do not read `/tests` (it is not present during your work anyway).

## Target program interface

```
/app/target/raycaster <grid-file>
```

Grid file format: the first line is `H W` (height, width). The next `H` lines
each contain `W` integers in the range `0..255`. The program prints several
lines to stdout and exits 0.

## Deliverables (both required)

1. `/app/reimpl.py` — a runnable **pure-Python** reimplementation:
   ```
   python3 /app/reimpl.py <grid-file>
   ```
   It must print the **identical bytes** to stdout that
   `/app/target/raycaster <grid-file>` prints, for **any** valid grid —
   including 1x1, 1xN, Nx1, wide grids, plateaus, exact ties, single-cell
   spikes, and values at the extremes 0 and 255.
   - `reimpl.py` must NOT invoke, load, exec, fork, or link the native binary
     (no subprocess, ctypes, or reading its bytes). The verifier rejects any
     reimplementation that references `/app/target` at all.
2. `/app/notes.md` — your reverse-engineering write-up. Document: the overall
   scene operation, any per-cell filtering pass and its exact window/edge
   rule, the ray/light model (direction, per-step falloff, strict vs
   non-strict comparisons), the exact output format, and how you confirmed
   each of these behaviors (which probes you ran).

## How to work

Build probe grids in `/tmp` and diff behaviors, e.g.:

```
/app/target/raycaster /tmp/probe1.txt
objdump -d /app/target/raycaster | less
```

Things the hidden verifier probes — make sure your model covers all of them:

- **Every comparison edge**: cells exactly level with an approaching ray
  (strict vs non-strict matters), descending ramps of exactly the per-step
  falloff, plateaus after a tall block.
- **The filtering pass**: single-cell spikes and pits, at interior positions
  and at row edges (first/last column), and in very narrow rows (W = 1, 2).
- **Edge cells** of every row (the ray starts somewhere specific) and rows of
  width 1 and 2.
- **Extremes**: heights 0 and 255, tall blocks that shadow long stretches,
  and grids up to 512x512.
- **Exact output format**: byte-for-byte, including the summary line and
  per-row lines.

## Constraints

- The verifier runs `/app/reimpl.py` unchanged on hidden grids and compares
  its stdout byte-for-byte against the pristine native binary's stdout, so
  do not hard-code to the provided fixture's contents.
- No network access at verify time; pure Python standard library only.
- Do not modify `/app/target/raycaster` or `/app/scene/grid.txt`.
