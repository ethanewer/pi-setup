#!/bin/bash
set -euo pipefail

cat > /app/grid.py <<'PY'
def expand(tile):
    # tile: 2x2 list-of-lists of ints -> 6x6 grid.
    # 1) tile 3x3 copies into 6x6
    A = [[tile[r % 2][c % 2] for c in range(6)] for r in range(6)]
    # 2) horizontal shift: row r shifted left by (r % 3)
    C = [[A[r][(c + (r % 3)) % 6] for c in range(6)] for r in range(6)]
    # 3) vertical shift: column c shifted down by (c % 3)
    return [[C[(r - (c % 3)) % 6][c] for c in range(6)] for r in range(6)]
PY

cat > /app/algo.py <<'PY'
def map(grid):
    n = len(grid)
    return [[grid[r][c] + grid[r][n - 1 - c] for c in range(n)] for r in range(n)]
PY

cat > /app/squares.py <<'PY'
def maximal_area(matrix):
    rows = len(matrix)
    if rows == 0:
        return 0
    cols = len(matrix[0])
    best = 0
    dp = [[0] * cols for _ in range(rows)]
    for r in range(rows):
        for c in range(cols):
            if matrix[r][c] == 1:
                if r == 0 or c == 0:
                    dp[r][c] = 1
                else:
                    dp[r][c] = min(dp[r - 1][c], dp[r][c - 1], dp[r - 1][c - 1]) + 1
                if dp[r][c] > best:
                    best = dp[r][c]
    return best * best
PY

python3 - <<'PY'
import grid
from session_core import MazeSession

tile = [[int(x) for x in line.split()] for line in open("/app/tile.txt") if line.strip()]
expanded = grid.expand(tile)

# Odd -> wall '#', even -> open '.'
marker = [["#" if v % 2 else "." for v in row] for row in expanded]

# start: top-most row, its left-most open '.'
for r in range(len(marker)):
    if "." in marker[r]:
        marker[r][marker[r].index(".")] = "S"
        break
# exit: bottom-most row, its right-most open '.'
for r in range(len(marker) - 1, -1, -1):
    if "." in marker[r]:
        ci = max(i for i, v in enumerate(marker[r]) if v == ".")
        marker[r][ci] = "E"
        break

rows = ["".join(row) for row in marker]
sess = MazeSession(rows)
sess.flag_visited([(r, c) for r, row in enumerate(marker)
                   for c in range(len(row)) if marker[r][c] == "."])
sess.finalize()
sess.write_map("/app/map.txt")
print("map written:")
print(open("/app/map.txt").read())
PY

echo "oracle complete"