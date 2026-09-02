#!/bin/bash
# Real oracle for sable-orbit: write the solve.py program, then RUN it on the
# visible fixture to produce /app/answer.txt. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.txt"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import math
import sys


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: solve.py <report.json> <out.txt>\n")
        return 2
    report_path, out_path = sys.argv[1], sys.argv[2]
    with open(report_path, "r", encoding="utf-8") as fh:
        report = json.load(fh)
    value = report["objective"]["reported"]
    n = math.floor(value)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("%d\n" % n)
    print(n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixture to generate the output.
python3 "$SOLVER" /app/settlement.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
