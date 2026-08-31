#!/bin/bash
# Oracle for fume-anchor: author the payload derivation program, then run it
# on the visible state directory to produce /app/answer.txt. Never reads /tests.
set -eu

SOLVER="/app/issue_token.py"
OUT="/app/answer.txt"

# ---- 1. Write the deliverable program (this IS the work).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Derive the fume-anchor activation payload from scattered clue artifacts."""
import os
import sys


def read_lines(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read().splitlines()


def base_value(state_dir):
    """B: last SERIES_BASE in deploy.env, ignoring blanks and # comments."""
    b = None
    for line in read_lines(os.path.join(state_dir, "deploy.env")):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        key, _, value = stripped.partition("=")
        if key.strip() == "SERIES_BASE":
            b = int(value.strip())
    return b


def multiplier(state_dir):
    """M: value of the exactly-named 'anchor' slot; last one wins."""
    m = None
    for line in read_lines(os.path.join(state_dir, "rotation.txt")):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        toks = stripped.split()
        if len(toks) >= 4 and toks[0] == "slot" and toks[2] == "=":
            if toks[1] == "anchor":
                m = int(toks[3])
    return m


def prime(state_dir):
    """P: first line containing 'epoch-prime'; integer after its last colon."""
    path = os.path.join(state_dir, "docs", "epoch.md")
    for line in read_lines(path):
        if "epoch-prime" in line:
            return int(line.rsplit(":", 1)[1].strip())
    raise ValueError("epoch-prime not found")


def offset(state_dir):
    """N: count of lines whose first whitespace token is exactly 'active'."""
    n = 0
    for line in read_lines(os.path.join(state_dir, "nodes.list")):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.split()[0] == "active":
            n += 1
    return n


def main():
    state_dir = sys.argv[1]
    b = base_value(state_dir)
    m = multiplier(state_dir)
    p = prime(state_dir)
    n = offset(state_dir)
    print((b * m + n) % p)


if __name__ == "__main__":
    main()
PY
chmod +x "$SOLVER"

# ---- 2. Run the produced program on the visible state to make the answer.
python3 "$SOLVER" /app/state > "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
cat "$OUT"
