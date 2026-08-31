#!/bin/bash
# Oracle for sable-ray: author the pure-Python reimplementation of the native
# target (median-of-3 despike + west->east raycast shadow pass) and the RE
# notes. Never reads /tests; the native binary stays untouched.
set -euo pipefail

REIMPL="/app/reimpl.py"
NOTES="/app/notes.md"

# ---- 1. The deliverable reimplementation (this IS the work). --------------
cat > "$REIMPL" <<'PY'
import sys


def med3(a, b, c):
    if a > b:
        a, b = b, a
    if b > c:
        b, c = c, b
    if a > b:
        a, b = b, a
    return b


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: reimpl.py <grid-file>\n")
        return 2
    with open(sys.argv[1]) as fh:
        header = fh.readline().split()
        H, W = int(header[0]), int(header[1])
        g = []
        for _ in range(H):
            row = [int(tok) & 0xFF for tok in fh.readline().split()]
            g.append(row)

    # Pass 1: horizontal median-of-3 despike with clamped window.
    s = []
    for y in range(H):
        row = []
        for x in range(W):
            xl = x - 1 if x > 0 else 0
            xr = x + 1 if x < W - 1 else W - 1
            row.append(med3(g[y][xl], g[y][x], g[y][xr]))
        s.append(row)

    # Pass 2: rays travel west -> east, clearance drops 1 per column step.
    # A cell is lit iff its smoothed height is STRICTLY greater than the best
    # ray clearance of every cell strictly west of it; column 0 is always lit.
    lines = []
    lit = 0
    for y in range(H):
        lev = -(1 << 30)
        chars = []
        for x in range(W):
            if x == 0:
                is_lit = True
            else:
                is_lit = s[y][x] > lev
            if is_lit:
                lit += 1
            chars.append("#" if is_lit else ".")
            down = s[y][x] - 1
            cand = lev - 1
            lev = cand if cand > down else down
        lines.append("".join(chars))

    out = ["LIT %d" % lit] + lines
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$REIMPL"

# ---- 2. Reverse-engineering notes (oracle-grade documentation). -----------
cat > "$NOTES" <<'MD'
# raycaster reverse-engineering notes

## Overall operation
`/app/target/raycaster` renders a terrain **sunlight/shadow mask**: given an
HxW heightmap it despikes each row, then marches light rays west->east and
prints `LIT <count>` followed by H rows of `#` (lit) / `.` (shadow).

## Pass 1 - despike (median-of-3, clamped)
Each height is replaced by the median of the horizontal 3-cell window
`g[y][x-1], g[y][x], g[y][x+1]` where out-of-row indices are **clamped** to
the row (x<0 -> 0, x>W-1 -> W-1). Confirmed by probes:

- `0 9 0 9 0` (1x5) yields an all-lit row `#####` -> the 9-spikes vanish
  under the median (without the filter they would light/shadow alternately).
- At row edges a 2-wide window is used: W=2 row `a b` -> `med(a,a,b)`,
  `med(a,b,b)`; W=1 rows are unchanged.
- Values are masked to 0..255 (`v & 0xff`) like typical 8-bit terrain.

## Pass 2 - raycast shadows (west->east, slope 1, strict)
Light rays start at the west edge and lose exactly **1 height unit of
clearance per column step**. Walking a row left to right with `lev` the best
clearance so far: column 0 is always lit; for x>0 the cell is lit iff
`smoothed[x] > lev` (STRICTLY greater - an exact tie is shadow). After each
column, `lev = max(lev - 1, smoothed[x] - 1)`. Confirmed by probes:

- Ramp `9 8 7 6 ...` (drop exactly 1/col) is shadow after column 0: `#....`
  -> proves the strict `>` (8 is NOT > 9-1=8) and the per-step falloff of 1.
- Flat plateau `5 5 5 5` is all lit (ray drops 1/col, terrain does not fall).
- `9 0 0 ...` shadows exactly 8 columns (ray from height 9 hits 0-floor
  after 9 steps) -> falloff confirmed quantitatively.
- Mirrored ramps light from the other end -> rays travel west->east only.
- Column 0 is lit even under an impossible overhang (e.g. height 255 at x=1).

## Output format
First line: `LIT <n>` where n = number of lit cells (total over all rows).
Then H lines of exactly W characters, `#` = lit, `.` = shadow, newline
terminated, no trailing spaces. Exit code 0.

## Method
Probe grids over: 1x1/1x2/2x1, spikes at x=0, x=1, interior, last column,
ties (descending-by-1 ramps), 0/255 extremes, 60-wide shadow-length probes;
cross-checked constants against the disassembly (integer median network,
`>` compare, and the `lev = max(lev-1, s-1)` recurrence).
MD

# ---- 3. Sanity: oracle reimpl must byte-match the native binary on the ----
# visible fixture and on a couple of locally generated probe grids.
tmp=$(mktemp -d)
printf '1 6\n9 8 7 6 5 4\n' > "$tmp/tie.txt"
printf '3 3\n255 0 0\n0 0 0\n0 0 255\n' > "$tmp/edge.txt"
for g in /app/scene/grid.txt "$tmp/tie.txt" "$tmp/edge.txt"; do
    a=$(/app/target/raycaster "$g")
    b=$(python3 "$REIMPL" "$g")
    if [ "$a" != "$b" ]; then
        echo "oracle mismatch vs native on $g" >&2
        exit 1
    fi
done
rm -rf "$tmp"

echo "solve.sh done -> $REIMPL and $NOTES"
ls -l "$REIMPL" "$NOTES"
