#!/bin/bash
# Oracle for opal-delta: write the generic solver, then RUN it on the shipped
# config to produce /app/expression.txt. Never reads /tests.
set -eu

SOLVER="/app/solver.py"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Farehaven toll-plate solver.

Finds an arithmetic expression over a subset of the allowed numbers (each
occurrence usable at most once, ops + - *) evaluating exactly to the target,
or writes IMPOSSIBLE.
"""
import json
import os
import sys
from collections import Counter


def search(nums, target):
    """Return a parenthesized expression or None.

    dp[mask] = dict value -> expression string built from exactly the numbers
    at the bit positions in mask (each occurrence used once).
    """
    n = len(nums)
    dp = [dict() for _ in range(1 << n)]
    for i in range(n):
        dp[1 << i][nums[i]] = str(nums[i])
    for mask in range(1, 1 << n):
        if mask & (mask - 1) == 0:
            continue
        entries = dp[mask]
        sub = (mask - 1) & mask
        while sub > 0:
            other = mask ^ sub
            if other:
                for a, ea in dp[sub].items():
                    for b, eb in dp[other].items():
                        if a + b not in entries:
                            entries[a + b] = "(%s+%s)" % (ea, eb)
                        if a - b not in entries:
                            entries[a - b] = "(%s-%s)" % (ea, eb)
                        if a * b not in entries:
                            entries[a * b] = "(%s*%s)" % (ea, eb)
            sub = (sub - 1) & mask
    for mask in range(1, 1 << n):
        if target in dp[mask]:
            return dp[mask][target]
    return None


def main():
    cfg_path, outdir = sys.argv[1], sys.argv[2]
    with open(cfg_path, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)
    allowed = [int(v) for v in cfg["allowed"]]
    target = int(cfg["target"])

    expr = search(allowed, target)
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, "expression.txt")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write((expr if expr is not None else "IMPOSSIBLE") + "\n")


if __name__ == "__main__":
    main()
PY
chmod +x "$SOLVER"

python3 "$SOLVER" /app/config.json /app

echo "solve.sh done -> $SOLVER and /app/expression.txt"
ls -l "$SOLVER" /app/expression.txt
cat /app/expression.txt
