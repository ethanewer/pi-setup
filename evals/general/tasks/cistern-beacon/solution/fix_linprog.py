#!/usr/bin/env python3
"""Apply sympy's linprog no-constraints fix to the checkout at /app/src.

In sympy/solvers/simplex.py, the no-constraints branch of linprog builds the
right-hand side as a C.cols x 1 zero column vector next to a 0 x C.cols A.
The row-count mismatch makes the internal _simplex routine see a truthy B
beside a falsy A and raise ValueError("must give A and B"), so an
unconstrained LP (cost row only) is never solved.  The fix builds b as a
0 x 1 zero matrix so the problem flows through as a 0-row problem: tolerable
costs return the trivial optimum (0, [0, ...]) and a cost row with a negative
entry raises UnboundedLPError.

Only the occurrence inside linprog is touched (the identical-looking line in
show_linprog is a different function and is left alone).  Idempotent; exits
non-zero if the expected snippet is not found.
"""

import sys
from pathlib import Path

BUGGY = "        A, b = zeros(0, C.cols), zeros(C.cols, 1)\n"
FIXED = "        A, b = zeros(0, C.cols), zeros(0, 1)\n"


def _span(lines: list[str], start_marker: str, end_marker: str) -> slice:
    start = next(i for i, l in enumerate(lines) if l.startswith(start_marker))
    end = next(i for i, l in enumerate(lines) if l.startswith(end_marker))
    return slice(start, end)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: fix_linprog.py PATH/TO/simplex.py", file=sys.stderr)
        return 2
    path = Path(argv[1])
    src = path.read_text(encoding="utf-8")
    lines = src.splitlines(keepends=True)
    span = _span(lines, "def linprog(", "def show_linprog(")
    if FIXED in lines[span]:
        print("simplex.py already carries the fix in linprog")
        return 0
    idx = next((i for i in range(span.start, span.stop) if lines[i] == BUGGY), None)
    if idx is None:
        print("FATAL: expected buggy line not found inside linprog:", file=sys.stderr)
        return 1
    lines[idx] = FIXED
    path.write_text("".join(lines), encoding="utf-8")
    print(f"ok: fixed linprog's no-constraints branch at line {idx + 1} of {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))