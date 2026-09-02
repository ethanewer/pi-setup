#!/usr/bin/env python3
"""
mp_entry.py
-----------
Container entry-point wrapper that runs a small multiprocessing job pool robustly.

Hard requirement: this module may be imported or executed from an arbitrary
directory inside the container, and it must never recursively re-run its own
main body when the multiprocessing runtime re-imports the module under
`__mp_main__` (the classic unguarded-spawn hang/duplication bug).

Implementation notes:
  * All worker logic lives in a top-level, picklable function `_square_plus`.
  * The main body is guarded by `if __name__ == "__main__":`.
  * An explicit 'spawn' start method is used so the exact container entry-point
    semantics are exercised on any platform.

With no arguments it computes [v*v + 3 for v in range(8)] across 4 workers and
prints a single marker plus the JSON result.  Passing an integer runs that many
workers.
"""
import json
import multiprocessing as mp
import sys

_MARKER = "MP_ENTRY_RUN"


def _square_plus(v):
    return v * v + 3


def main():
    nprocs = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    ctx = mp.get_context("spawn")
    vals = list(range(12))
    with ctx.Pool(processes=nprocs) as pool:
        results = pool.map(_square_plus, vals)
    expected = [v * v + 3 for v in vals]
    print(_MARKER, flush=True)
    print(json.dumps({"ok": results == expected, "results": results}), flush=True)


if __name__ == "__main__":
    main()