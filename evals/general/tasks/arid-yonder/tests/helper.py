#!/usr/bin/env python3
"""Compare two files of a given kind. Returns 0 when equal, 1 otherwise."""
import sys
import json


def norm_tsv(path):
    lines = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            lines.append(line.rstrip("\r\n").rstrip())
    while lines and lines[-1] == "":
        lines.pop()
    return lines


def main():
    if len(sys.argv) != 4:
        return 2
    kind, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
    if kind == "tsv":
        return 0 if norm_tsv(a) == norm_tsv(b) else 1
    if kind == "json":
        try:
            ja = json.load(open(a, encoding="utf-8"))
            jb = json.load(open(b, encoding="utf-8"))
        except Exception:
            return 1
        return 0 if ja == jb else 1
    return 2


if __name__ == "__main__":
    sys.exit(main())