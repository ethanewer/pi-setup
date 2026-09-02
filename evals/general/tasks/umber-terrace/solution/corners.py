"""corners.py -- enumerate every basic feasible solution (corner) of a
nonnegative linear program.

A(x) = b , x >= 0  with m equations and n unknowns (n >= m).

Method (per the competency):  pick every subset of exactly m columns, solve the
resulting square linear subsystem, and keep the solutions whose m selected
entries are all nonnegative.  Duplicates (identical full vectors, up to rounding)
are collapsed.

Usage:  python3 /app/corners.py <INPUT.json> <OUTPUT.txt>
    INPUT.json  : {"A": [[...]], "b": [...], "tol": 1e-9}
                  A has m rows and n columns (list of lists or array).
    OUTPUT.txt  : line 1 -> "<K>"  number of distinct corners
                  then K lines, each the space-separated x_1..x_n of a corner.
"""
import sys
import itertools
import json
import numpy as np


def all_corners(A, b, tol=1e-9):
    """Return sorted unique nonnegative basic feasible solutions."""
    A = np.asarray(A, dtype=float)
    b = np.asarray(b, dtype=float).reshape(-1)
    m, n = A.shape
    if b.size != m:
        raise ValueError("b length must equal the number of rows of A")
    corners = set()
    for cols in itertools.combinations(range(n), m):
        B = A[:, cols]
        try:
            xB = np.linalg.solve(B, b)
        except np.linalg.LinAlgError:
            continue
        if np.any(xB < -tol):         # violates nonnegativity
            continue
        full = np.zeros(n)
        full[list(cols)] = xB
        key = tuple(np.round(full, 8))
        corners.add(key)
    return corners


def main():
    import sys
    if len(sys.argv) < 3:
        sys.stderr.write("usage: corners.py <INPUT.json> <OUTPUT.txt>\n")
        sys.exit(2)
    inp, out = sys.argv[1], sys.argv[2]
    data = json.load(open(inp))
    tol = float(data.get("tol", 1e-9))
    corners = all_corners(data["A"], data["b"], tol)
    lines = [str(len(corners))]
    for c in corners:
        lines.append(" ".join(f"{float(x):.15g}" for x in c))
    with open(out, "w") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()