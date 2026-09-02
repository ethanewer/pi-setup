#!/bin/bash
# Oracle for juniper-latch: rewrite the sanctioned file /app/sigdeck/windowing.py
# to the fixed implementation and smoke-run the package on the visible input.
# Never reads /tests.
set -eu

TARGET="/app/sigdeck/windowing.py"

cat > "$TARGET" <<'PY'
"""Windowing math for the sigdeck analysis stage (3.1.0 interface spec)."""

import math

from .constants import LADDER


def moving_rms(values, W):
    """Trailing-window RMS: window(i) = values[max(0, i-W+1) : i+1],
    never padded; result rounded to 4 decimals."""
    out = []
    for i in range(len(values)):
        seg = values[max(0, i - W + 1):i + 1]
        rms = math.sqrt(sum(v * v for v in seg) / len(seg))
        out.append(round(rms, 4))
    return out


def quantize(x, ladder=None):
    """Largest rung r with r <= x; exact ties map to that rung."""
    ladder = LADDER if ladder is None else ladder
    rung = ladder[0]
    for r in ladder:
        if r <= x:
            rung = r
    return rung
PY

# Smoke-run the repaired package on the supplied visible input.
python3 -m sigdeck.runner /app/input.csv /tmp/oracle_smoke/report.json
python3 - <<'PY'
import json
with open("/tmp/oracle_smoke/report.json") as fh:
    rep = json.load(fh)
assert rep["count"] == 60 and len(rep["rms"]) == 60 and len(rep["rung"]) == 60
assert rep["rms"][0] == 1.0 and rep["rung"][0] == 1.0  # exact tie -> up
print("oracle smoke ok:", rep["rms"][:4], rep["rung"][:4])
PY

echo "solve.sh done -> $TARGET"
