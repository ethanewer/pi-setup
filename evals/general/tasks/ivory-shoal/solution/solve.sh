#!/bin/bash
# Real oracle for ivory-shoal: write the plasmid tag designer, then RUN it on
# the visible parameters to produce /app/plasmid_out.txt. Never reads /tests.
set -eu

SOLVER="/app/plasmid.py"
OUT="/app/plasmid_out.txt"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Design a circular plasmid tag whose windows obey a two-base composition rule."""
import math
import sys
from fractions import Fraction
from pathlib import Path

BASES = "ACGT"


def design(length, window, lo, hi, pair):
    loF, hiF = Fraction(lo), Fraction(hi)
    others = [b for b in BASES if b not in pair]
    kmin = max(2, math.ceil(loF * window / 100))
    kmax = min(window - 3, math.floor(hiF * window / 100))
    if kmin > kmax:
        raise ValueError("no feasible k for the given parameters")
    k = kmin

    # period block of length <window>: pair letters at evenly spaced positions,
    # alternating between the two pair bases; remaining slots alternate the
    # two other bases.
    positions = sorted({(i * window) // k for i in range(k)})
    assert len(positions) == k
    block = []
    for i in range(window):
        if i in positions:
            block.append(pair[len([p for p in positions if p <= i]) % 2])
        else:
            block.append(others[len(block) % 2])

    tag = ("".join(block) * (length // window + 2))[:length]

    # ---- self-check: every constraint, computed independently ----
    circ = tag + tag
    assert len(tag) == length and set(tag) <= set(BASES)
    assert all(b in tag for b in BASES)
    extended = tag + tag[:8]
    max_run, cur = 1, 1
    for i in range(1, len(extended)):
        cur = cur + 1 if extended[i] == extended[i - 1] else 1
        max_run = max(max_run, cur)
    assert max_run <= 4, "homopolymer run %d" % max_run
    for start in range(length):
        seg = circ[start:start + window]
        cnt = sum(1 for b in seg if b in pair)
        pct = Fraction(100 * cnt, window)
        assert loF <= pct <= hiF, (start, float(pct))
    return tag


def main():
    out_path = Path(sys.argv[1])
    length, window = int(sys.argv[2]), int(sys.argv[3])
    lo, hi = sys.argv[4], sys.argv[5]   # keep as strings; Fraction parses exactly
    pair = "".join(sorted(sys.argv[6].upper()))
    assert len(pair) == 2 and pair[0] in BASES and pair[1] in BASES and pair[0] != pair[1]
    tag = design(length, window, lo, hi, pair)
    out_path.write_text(tag + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" "$OUT" 1200 80 32 44 GC

echo "solve.sh done -> $SOLVER and $OUT"
wc -c "$OUT"
