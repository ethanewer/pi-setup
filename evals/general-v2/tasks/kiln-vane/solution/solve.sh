#!/bin/bash
# Real oracle for kiln-vane: write the general weave() module, then RUN it on the
# visible fixture to produce /app/swatch.json. Never reads /tests.
set -eu

MODULE="/app/loom.py"
OUT="/app/swatch.json"

cat > "$MODULE" <<'PY'
#!/usr/bin/env python3
"""Kiln Vane swatch expander: fold a 2x2 tile into a 6x6 swatch."""
import json
import sys

N = 6


def weave(tile):
    """Expand a 2x2 tile into a 6x6 swatch.

    1. Tile the 6x6 with 3x3 copies of `tile`.
    2. Shift every row r circularly RIGHT by ((r + 1) % 3) columns.
    3. Shift every column c circularly UP by ((c + 2) % 3) rows.
    """
    if not (isinstance(tile, list) and len(tile) == 2
            and all(isinstance(row, list) and len(row) == 2 for row in tile)):
        raise ValueError("tile must be a 2x2 list-of-lists")

    # Step 1: tiling.
    tiled = [[tile[r % 2][c % 2] for c in range(N)] for r in range(N)]

    # Step 2: horizontal circular shift right by ((r + 1) % 3).
    hshift = [[tiled[r][(c - ((r + 1) % 3)) % N] for c in range(N)]
              for r in range(N)]

    # Step 3: vertical circular shift up by ((c + 2) % 3).
    out = [[hshift[(r + ((c + 2) % 3)) % N][c] for c in range(N)]
           for r in range(N)]
    return out


def main(argv):
    if len(argv) != 3:
        print("usage: loom.py <tile_json> <output_json>", file=sys.stderr)
        return 2
    with open(argv[1], "r", encoding="utf-8") as fh:
        data = json.load(fh)
    swatch = weave(data["tile"])
    with open(argv[2], "w", encoding="utf-8") as fh:
        json.dump(swatch, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x "$MODULE"

python3 "$MODULE" /app/tile.json "$OUT"

echo "solve.sh done -> $MODULE and $OUT"
ls -l "$MODULE" "$OUT"
