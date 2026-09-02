#!/bin/bash
# Real oracle for crimson-fjord: write the solve.py program, then RUN it on the
# visible fixture to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import sys


def is_num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def main():
    in_path, out_path = sys.argv[1], sys.argv[2]

    counts = {}
    totals = {}
    tips = 0
    skipped = 0

    with open(in_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue  # blank lines: ignored, not skipped
            try:
                rec = json.loads(line)
            except (ValueError, TypeError):
                skipped += 1
                continue
            if not isinstance(rec, dict):
                skipped += 1
                continue
            tag = rec.get("tag")
            amount = rec.get("amount")
            if not isinstance(tag, str) or not is_num(amount):
                skipped += 1
                continue
            tips += 1
            counts[tag] = counts.get(tag, 0) + 1
            totals[tag] = totals.get(tag, 0.0) + amount

    tags = {}
    for tag in counts:
        tags[tag] = {
            "count": counts[tag],
            "amount": round(float(totals[tag]), 2),
        }

    report = {"tips": tips, "skipped": skipped, "tags": tags}
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixture to generate the output.
python3 "$SOLVER" /app/pulse.jsonl "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
