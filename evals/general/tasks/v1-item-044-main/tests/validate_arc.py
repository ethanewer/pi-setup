#!/usr/bin/env python3
"""Hidden ARC-AGI schema validator for item-044.

Usage: python3 validate_arc.py <tasks-dir>
Checks every *.json in <tasks-dir>:
  - parses as JSON object
  - has "train" and "test" lists
  - every example has "input" and "output" keys
  - each grid is a non-empty list of rows; each row a list of ints 0..9;
    all rows of the same grid have equal length.
Exits 0 iff all files are valid.
"""
import json
import sys
import os


def valid_grid(g):
    if not isinstance(g, list) or len(g) == 0:
        return False
    n = len(g[0])
    for row in g:
        if not isinstance(row, list) or len(row) != n or len(row) == 0:
            return False
        for cell in row:
            if not isinstance(cell, int) or isinstance(cell, bool) or not (0 <= cell <= 9):
                return False
    return True


def valid_task(obj):
    if not isinstance(obj, dict):
        return False
    for key in ("train", "test"):
        v = obj.get(key)
        if not isinstance(v, list):
            return False
        for ex in v:
            if not isinstance(ex, dict) or "input" not in ex or "output" not in ex:
                return False
            if not valid_grid(ex["input"]) or not valid_grid(ex["output"]):
                return False
    return True


def main():
    d = sys.argv[1]
    files = sorted(f for f in os.listdir(d) if f.endswith(".json"))
    if not files:
        return 1
    for f in files:
        try:
            obj = json.load(open(os.path.join(d, f)))
        except Exception:
            return 1
        if not valid_task(obj):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())