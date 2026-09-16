#!/usr/bin/env python3
"""Independent expectation for a cache-clean accounting hidden case.

The expectation must be computed WITHOUT the uv binary: it is the disk space
genuinely reclaimed by deleting the given files, derived purely from the
filesystem metadata of the files the case just created:

    sum(file.size_in_blocks() * 512)  over files with a link count of exactly 1

because a file whose storage is shared with a surviving hard link (nlink != 1
at the moment it is deleted) frees nothing, and a file's own length does not
matter - what occupies the disk is its allocated blocks (st_blocks is always
in 512-byte units, whatever the filesystem block size).

Then it formats the total the same way uv formats its reported figure
(human_readable_bytes at one decimal, IEC units), so the case can compare the
string byte-for-byte with the suffix uv actually prints.

Usage:
    python3 /tests/hidden/_lib/expect.py FILE...     -> prints the expected
    parenthesised figure, e.g. `(0B)` or `(1.0MiB)`.

Exit status is 1 if any named file no longer exists (the deletion already
happened, so the case setup is broken), else 0.
"""

from __future__ import annotations

import os
import sys

UNITS = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]


def fmt_bytes(n: int) -> str:
    """Mirror uv-console human_readable_bytes at one-decimal precision."""
    if n < 1024:
        return f"{n}B"
    margin = 0.05  # 0.5 / 10^1
    quantity = float(n)
    unit = 0
    for i in range(1, len(UNITS)):
        if 1024.0 - quantity > margin:
            break
        quantity /= 1024.0
        unit = i
    return f"{quantity:.1f}{UNITS[unit]}"


def reclaimed(rel: str, work: str) -> int:
    path = os.path.join(work, rel)
    st = os.lstat(path)
    return st.st_blocks * 512 if st.st_nlink == 1 else 0


def main() -> None:
    args = sys.argv[1:]
    if len(args) < 2:
        print("usage: expect.py WORK_DIR RELFILE...", file=sys.stderr)
        raise SystemExit(2)
    work, rels = args[0], args[1:]
    missing = [r for r in rels if not os.path.lexists(os.path.join(work, r))]
    if missing:
        print("missing files before deletion: " + ", ".join(missing), file=sys.stderr)
        raise SystemExit(1)
    total = sum(reclaimed(r, work) for r in rels)
    print(f"({fmt_bytes(total)})")


if __name__ == "__main__":
    main()