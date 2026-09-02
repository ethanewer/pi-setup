#!/usr/bin/env python3
"""Dune-core canonical puzzle-state serialiser.

Each board configuration is serialised as a fixed-length string of two-digit
tiles in row-major order. The canonical form has exactly 2 characters per tile
(each value zero-padded to two digits) and never shortens or skips squares.

CLI:
    python3 serialize.py <input.json> <output.json>

input.json  ->  [ board_0, board_1, ... ]   (each board = list of rows;
                                             each row  = list of tile integers)
output.json ->  [ string_0 , string_1, ... ]   (same order)

Canonical encoding for board B (rows R, cols C):
    "".join( "%02d" % B[r][c] for r in range(R) for c in range(C) )
Length is exactly R*C*2 for every valid board.

Validation:
  - a board that is not a non-empty list of rows -> "INVALID"
  - a row that is not a same-length list of integers, or an out-of-range
    value (not 0..99), makes that single board "INVALID" (others unaffected)
  - leading zeros are required (e.g. tile 7 encodes as "07").
"""

import sys
import json


def serialize(board):
    if not isinstance(board, list) or not board:
        return "INVALID"
    width = None
    parts = []
    for row in board:
        if not isinstance(row, list):
            return "INVALID"
        if width is None:
            width = len(row)
            if width == 0:
                return "INVALID"
        if len(row) != width:
            return "INVALID"
        for v in row:
            if not isinstance(v, int) or isinstance(v, bool) or not (0 <= v <= 99):
                return "INVALID"
            parts.append("%02d" % v)
    return "".join(parts)


def main():
    inp, outp = sys.argv[1], sys.argv[2]
    with open(inp, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, list):
        raise ValueError("input must be a JSON list of boards")
    out = [serialize(b) for b in data]
    with open(outp, "w", encoding="utf-8") as fh:
        json.dump(out, fh)
    sys.stdout.write("ok\n")


if __name__ == "__main__":
    main()