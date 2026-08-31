#!/bin/bash
# Real oracle for copper-quill: write the score.py program, then RUN it on the
# visible fixtures to produce /app/report.json. Never reads /tests.
set -eu

SOLVER="/app/score.py"
OUT="/app/report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import math
import sys


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def round_half_up(x, nd=3):
    scaled = x * (10 ** nd)
    return math.floor(scaled + 0.5) / (10 ** nd)


def score(model, truth):
    rounds = sorted(set(model) | set(truth))
    report = []
    for rid in rounds:
        m = model.get(rid, {})
        t = truth.get(rid, {})
        correct = 0
        total = 0
        for qid in m.keys() & t.keys():
            mv = m[qid]
            tv = t[qid]
            if not is_number(mv) or not is_number(tv):
                continue  # invalid pair: dropped entirely
            total += 1
            if mv == tv:
                correct += 1
        if total == 0:
            accuracy = None
        else:
            accuracy = round_half_up(correct / total, 3)
            accuracy = min(1.0, max(0.0, accuracy))
        report.append(
            {"round": rid, "correct": correct, "total": total, "accuracy": accuracy}
        )
    return report


def main():
    model_path, truth_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(model_path, "r", encoding="utf-8") as fh:
        model = json.load(fh)
    with open(truth_path, "r", encoding="utf-8") as fh:
        truth = json.load(fh)
    report = score(model, truth)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the report.
python3 "$SOLVER" /app/model.json /app/key.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"