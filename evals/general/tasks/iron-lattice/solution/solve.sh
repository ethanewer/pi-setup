#!/bin/bash
# iron-lattice oracle: writes the real power-iteration program, then RUNS it on
# the visible matrix to produce an output. It never reads /tests and never cats
# precomputed answers. The verifier re-runs the produced program on hidden cases.
set -eu
mkdir -p /app

cat > /app/power.py <<'PY'
#!/usr/bin/env python3
"""Power iteration for the dominant mode of a real symmetric matrix.

Usage: python3 power.py <matrix_file> <output_json_path>
Writes JSON: {"eigenvalue": float, "vector": [normalized unit vector]}
"""
import json
import math
import sys


def load_matrix(path):
    with open(path) as f:
        rows = [[x for x in line.split()] for line in f if line.strip()]
    if not rows:
        raise SystemExit("error: empty matrix")
    n = len(rows)
    A = []
    for r in rows:
        if len(r) != n:
            raise SystemExit("error: matrix is not square")
        A.append([float(x) for x in r])
    return A


def power_loop(A, tol=1e-10, max_iter=200000):
    n = len(A)
    v = [1.0] * n
    scale = math.sqrt(sum(x * x for x in v))
    v = [x / scale for x in v]
    for _ in range(max_iter):
        w = [0.0] * n
        for i in range(n):
            row = A[i]
            s = 0.0
            for j in range(n):
                s += row[j] * v[j]
            w[i] = s
        wscale = math.sqrt(sum(x * x for x in w))
        w = [x / wscale for x in w]
        delta = math.sqrt(sum((w[i] - v[i]) ** 2 for i in range(n)))
        v = w
        if delta < tol:
            break
    # Rayleigh quotient for the eigenvalue: v^T A v
    w = [sum(A[i][j] * v[j] for j in range(n)) for i in range(n)]
    ev = sum(w[i] * v[i] for i in range(n))
    return ev, v


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: python3 power.py <matrix_file> <output_file>")
    infile, outfile = sys.argv[1], sys.argv[2]
    A = load_matrix(infile)
    ev, v = power_loop(A)
    obj = {"eigenvalue": ev, "vector": v}
    with open(outfile, "w") as f:
        json.dump(obj, f)


if __name__ == "__main__":
    main()
PY

chmod +x /app/power.py

# Produce the visible answer by running the program (real work), then succeed.
python3 /app/power.py /app/matrix.txt /app/visible_answer.json
echo "done"