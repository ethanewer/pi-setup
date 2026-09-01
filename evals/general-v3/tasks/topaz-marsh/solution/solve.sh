#!/bin/bash
# Real oracle for topaz-marsh: write the exact weighted Max-SAT solver, then
# RUN it on the visible instance to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/wmaxsat.py"
OUT="/app/answer.json"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Exact weighted Max-SAT solver (MILP encoding via scipy.optimize.milp/HiGHS).

Variables: x_1..x_n binary, plus a continuous s_j in [0,1] per soft clause.
For clause j, expr_j = sum of sign-matched literals is linear in x:
    expr_j = sum_pos x_i + sum_neg (1 - x_i)
Hard clauses: expr_j >= 1.  Soft clauses: s_j <= expr_j, objective max sum w_j s_j
(s_j is pushed to 1 exactly when the clause is satisfied). The optimum is integral.
"""
import json
import sys

import numpy as np
from scipy.optimize import milp, LinearConstraint, Bounds


def parse(path):
    nvars = None
    hard, soft = [], []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("c"):
                continue
            parts = line.split()
            if parts[0] == "p":
                assert parts[1] == "wcnf"
                nvars = int(parts[2])
                continue
            assert parts[-1] == "0", line
            lits = [int(t) for t in parts[1:-1]]
            if parts[0] == "h":
                hard.append(lits)
            else:
                soft.append((int(parts[0]), lits))
    return nvars, hard, soft


def solve(nvars, hard, soft):
    m = len(soft)
    N = nvars + m
    c = np.zeros(N)
    if m:
        c[nvars:] = -np.array([w for w, _ in soft], dtype=float)
    integrality = np.zeros(N)
    integrality[:nvars] = 1

    def expr_row(lits):
        row = np.zeros(N)
        const = 0.0
        for l in lits:
            i = abs(l) - 1
            if l > 0:
                row[i] += 1.0
            else:
                row[i] -= 1.0
                const += 1.0
        return row, const

    rows, lbs, ubs = [], [], []
    for lits in hard:
        row, const = expr_row(lits)
        rows.append(row)
        lbs.append(1.0 - const)
        ubs.append(np.inf)
    for j, (w, lits) in enumerate(soft):
        row, const = expr_row(lits)
        srow = np.zeros(N)
        srow[nvars + j] = 1.0
        rows.append(srow - row)          # s_j - expr_row . x <= const  <=>  s_j <= expr_j
        lbs.append(-np.inf)
        ubs.append(const)
    A = np.array(rows) if rows else np.zeros((0, N))
    res = milp(
        c=c,
        constraints=LinearConstraint(A, np.array(lbs), np.array(ubs)),
        integrality=integrality,
        bounds=Bounds(np.zeros(N), np.ones(N)),
        options={"time_limit": 110},
    )
    if res.status == 2:
        return {"status": "HARD_UNSAT"}
    if res.status != 0:
        raise RuntimeError("solver did not prove optimality (status %d)" % res.status)
    return {"status": "OPTIMAL", "objective": int(round(-res.fun))}


def main():
    inst_path, out_path = sys.argv[1], sys.argv[2]
    nvars, hard, soft = parse(inst_path)
    result = solve(nvars, hard, soft)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/instances/visible.wcnf "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
cat "$OUT"
