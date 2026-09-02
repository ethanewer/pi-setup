#!/usr/bin/env python3
"""Reference solver used by test.sh. Computes expected answers independently
of the agent's implementation and compares, command by command.

Usage:
    ref.py expand <json-file>     # tile_*.json    -> compare app/tile grid.py.expand
    ref.py arc <json-file>        # arc_*.json     -> compare app/algo.py.map
    ref.py sq <json-file>         # sq_*.json      -> compare app/squares.py.maximal_area
    ref.py mapfile                # compare /app/map.txt (from /app/tile.txt)
"""
import importlib.util
import json
import sys


def load_mod(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def ref_expand(tile):
    A = [[tile[r % 2][c % 2] for c in range(6)] for r in range(6)]
    C = [[A[r][(c + (r % 3)) % 6] for c in range(6)] for r in range(6)]
    return [[C[(r - (c % 3)) % 6][c] for c in range(6)] for r in range(6)]


def ref_map(grid):
    n = len(grid)
    return [[grid[r][c] + grid[r][n - 1 - c] for c in range(n)] for r in range(n)]


def ref_map_rows(marker):
    rows = [list(r) for r in marker]
    for r in range(len(rows)):
        if "." in rows[r]:
            rows[r][rows[r].index(".")] = "S"
            break
    for r in range(len(rows) - 1, -1, -1):
        if "." in rows[r]:
            ci = max(i for i, v in enumerate(rows[r]) if v == ".")
            rows[r][ci] = "E"
            break
    return ["".join(row) for row in rows]


def ref_mapfile():
    tile = [[int(x) for x in line.split()]
            for line in open("/app/tile.txt") if line.strip()]
    exp = ref_expand(tile)
    marker = ["".join("#" if v % 2 else "." for v in row) for row in exp]
    return ref_map_rows(marker)


def norm_map(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def main():
    cmd = sys.argv[1]
    if cmd == "expand":
        data = json.load(open(sys.argv[2]))
        expected = ref_expand(data)
        got = load_mod("/app/grid.py", "grid").expand(data)
        ok = got == expected
    elif cmd == "arc":
        data = json.load(open(sys.argv[2]))
        expected = ref_map(data)
        got = load_mod("/app/algo.py", "algo").map(data)
        ok = got == expected
    elif cmd == "sq":
        data = json.load(open(sys.argv[2]))
        expected = ref_area_sq(data)
        got = load_mod("/app/squares.py", "squares").maximal_area(data)
        ok = got == expected
    elif cmd == "mapfile":
        expected = ref_mapfile()
        try:
            got = norm_map(open("/app/map.txt").read())
        except Exception:
            ok = False
        else:
            exp = [line.strip() for line in expected]
            ok = got == exp
    else:
        print("FAIL unknown cmd")
        sys.exit(1)
    print("OK" if ok else "FAIL")
    sys.exit(0 if ok else 1)


def ref_area_sq(data):
    rows = len(data)
    if rows == 0:
        return 0
    cols = len(data[0])
    best = 0
    dp = [[0] * cols for _ in range(rows)]
    for r in range(rows):
        for c in range(cols):
            if data[r][c] == 1:
                if r == 0 or c == 0:
                    dp[r][c] = 1
                else:
                    dp[r][c] = min(dp[r - 1][c], dp[r][c - 1], dp[r - 1][c - 1]) + 1
                best = max(best, dp[r][c])
    return best * best


if __name__ == "__main__":
    main()