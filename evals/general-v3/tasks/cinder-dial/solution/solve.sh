#!/bin/bash
# Oracle for cinder-dial: write the scorer program, then RUN it on the visible
# fixture to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/rounds.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import math
import sys


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def half_up(x):
    return math.floor(x * 1000 + 0.5) / 1000


def score(pred, truth):
    rounds = sorted(set(pred) | set(truth), key=lambda r: int(r))
    out_rounds = []
    oc = ot = 0
    for r in rounds:
        p, t = pred.get(r, {}), truth.get(r, {})
        c = tot = 0
        for q in p.keys() & t.keys():
            pv, tv = p[q], t[q]
            if not (is_number(pv) and is_number(tv)):
                continue  # invalid / error marker on either side: dropped
            tot += 1
            if pv == tv:
                c += 1
        oc += c
        ot += tot
        out_rounds.append({
            "round": r,
            "correct": c,
            "total": tot,
            "accuracy": half_up(c / tot) if tot else None,
        })
    return {
        "overall": {
            "correct": oc,
            "total": ot,
            "accuracy": half_up(oc / ot) if ot else None,
        },
        "rounds": out_rounds,
    }


def main():
    in_path, out_path = sys.argv[1], sys.argv[2]
    with open(in_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    answer = score(data.get("predictions", {}), data.get("truth", {}))
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixture to generate the output.
python3 "$SOLVER" /app/rounds.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
