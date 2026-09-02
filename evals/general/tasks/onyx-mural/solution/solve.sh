#!/bin/bash
# Real oracle for onyx-mural: write the reimplementation deliverable and the
# notes, then SELF-CHECK the reimplementation against the native binary on the
# visible grids and deterministic synthetic probes. Never reads /tests.
set -eu

REIMPL="/app/reimpl.py"
NOTES="/app/notes.md"

# ---- 1. The deliverable program (a faithful reimplementation of the target).
cat > "$REIMPL" <<'PY'
#!/usr/bin/env python3
"""Standalone reimplementation of /app/scene/mural.

Discovered model (see /app/notes.md): serpentine error-diffusion (Floyd-
Steinberg) dithering to two levels 0/255 with threshold 128, weights
7/16 (ahead), 3/16 (behind-below), 5/16 (below), 1/16 (ahead-below),
C-truncating integer division, error propagated in-place onto a grid of
accumulated offsets; output is one line of '#'/'.' per grid row.
"""
import sys


def tdiv(a, b):
    """C-style truncating integer division (rounds toward zero)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: reimpl.py <grid-file>", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], "r") as fh:
        toks = fh.read().split()
    it = iter(toks)
    try:
        h = int(next(it))
        w = int(next(it))
    except StopIteration:
        sys.exit(2)
    px = [[int(next(it)) & 0xFF for _ in range(w)] for _ in range(h)]
    err = [[0] * w for _ in range(h)]
    out = []
    for y in range(h):
        l2r = (y % 2 == 0)
        row = []
        for k in range(w):
            x = k if l2r else (w - 1 - k)
            old = px[y][x] + err[y][x]
            new = 255 if old >= 128 else 0
            e = old - new
            row.append('#' if new == 255 else '.')
            if l2r:
                if x + 1 < w:
                    err[y][x + 1] += tdiv(e * 7, 16)
                if x - 1 >= 0 and y + 1 < h:
                    err[y + 1][x - 1] += tdiv(e * 3, 16)
                if y + 1 < h:
                    err[y + 1][x] += tdiv(e * 5, 16)
                if x + 1 < w and y + 1 < h:
                    err[y + 1][x + 1] += tdiv(e * 1, 16)
            else:
                if x - 1 >= 0:
                    err[y][x - 1] += tdiv(e * 7, 16)
                if x + 1 < w and y + 1 < h:
                    err[y + 1][x + 1] += tdiv(e * 3, 16)
                if y + 1 < h:
                    err[y + 1][x] += tdiv(e * 5, 16)
                if x - 1 >= 0 and y + 1 < h:
                    err[y + 1][x - 1] += tdiv(e * 1, 16)
        out.append(''.join(row))
    sys.stdout.write(''.join(r + '\n' for r in out))


if __name__ == "__main__":
    main()
PY
chmod +x "$REIMPL"

# ---- 2. Engineering notes describing the reverse-engineered operation.
cat > "$NOTES" <<'MD'
# Reverse-engineering notes: `/app/scene/mural`

## Operation

The binary performs **1-bit serpentine error-diffusion dithering**
(a Floyd-Steinberg variant) of a grayscale grid and renders the result as
ASCII art.

## Input format

Whitespace-separated integer tokens: the first two tokens are `H` (height) and
`W` (width); the next `H*W` tokens are pixel values in row-major order, each
taken modulo 256 (`& 0xff`).

## Algorithm (per pixel, discovered by probing + objdump)

1. Scan rows top to bottom. **Serpentine scan**: even rows are scanned left to
   right; odd rows are scanned right to left.
2. For each pixel, `old = value + err[y][x]` where `err` is an in-place grid of
   accumulated error terms (initially 0).
3. Quantize: `new = 255 if old >= 128 else 0` (threshold 128, two levels).
4. The residual `e = old - new` is propagated to not-yet-processed neighbors
   with weights (integer arithmetic, C truncating division `e*w/16`):
   - `7/16` to the next pixel **in scan direction** on the same row,
   - `3/16` to the pixel **behind** the scan direction one row below,
   - `5/16` to the pixel directly below,
   - `1/16` to the pixel **ahead** of the scan direction one row below.
   Proposals that fall outside the grid (first/last column, last row) are
   dropped (no wrapping).
5. Output character per pixel: `#` for the 255 level, `.` for the 0 level.

## Output format

Exactly `H` lines; each line is `W` characters (`#` or `.`) with **no spaces**,
each line terminated by a single `\n` (including the last). Nothing else is
printed to stdout.

## Evidence

- A constant 128-grid yields a stable '#'/'.' texture only under error
  diffusion (a pure threshold would give a flat line); the pattern shifts with
  row parity -> serpentine order.
- A single 255 pixel in a dark grid bleeds exactly (7,3,5,1)/16 into its
  raster-right / below-left / below / below-right neighbors on even rows and
  the mirrored set on odd rows.
- Negative residuals propagate with truncation toward zero (verified with
  asymmetric probes around the threshold).
MD

# ---- 3. Self-check: the reimplementation must byte-match the native binary.
python3 - <<'PY'
import glob, os, random, subprocess, sys, tempfile

fails = []
grids = sorted(glob.glob('/app/grids/*.txt'))
random.seed(9001)
cases = []
for g in grids:
    cases.append(('visible:' + os.path.basename(g), open(g).read()))
cases.append(('1x1-0', '1 1 0'))
cases.append(('1x1-255', '1 1 255'))
cases.append(('1x1-127', '1 1 127'))
cases.append(('1x1-128', '1 1 128'))
cases.append(('col', '5 1 200 100 50 25 9'))
cases.append(('row', '1 6 255 254 200 10 0'))
for _ in range(25):
    H = random.randint(1, 24); W = random.randint(1, 24)
    cases.append((f'{H}x{W}-rand', ' '.join(map(str, [H, W] + [random.randint(0, 255) for _ in range(H * W)]))))
for H, W in [(13, 9)]:
    for v in (0, 127, 128, 255):
        cases.append((f'{H}x{W}-const{v}', ' '.join(map(str, [H, W] + [v] * (H * W)))))

with tempfile.TemporaryDirectory() as td:
    for name, text in cases:
        p = os.path.join(td, 'g.txt')
        with open(p, 'w') as f:
            f.write(text + '\n')
        nat = subprocess.run(['/app/scene/mural', p], capture_output=True, timeout=60)
        rei = subprocess.run([sys.executable, '/app/reimpl.py', p], capture_output=True, timeout=60)
        if nat.returncode != 0:
            fails.append(f'{name}: native rc={nat.returncode}')
        elif rei.returncode != 0:
            fails.append(f'{name}: reimpl rc={rei.returncode} ({rei.stderr.decode()[:80]})')
        elif rei.stdout != nat.stdout:
            fails.append(f'{name}: reimpl stdout != native stdout')

if fails:
    print('ORACLE SELF-CHECK FAILURES:', fails)
    sys.exit(1)
print(f'ORACLE SELF-CHECK OK ({len(cases)} probe grids byte-identical)')
PY

echo "solve.sh done -> $REIMPL and $NOTES"
ls -l "$REIMPL" "$NOTES"
