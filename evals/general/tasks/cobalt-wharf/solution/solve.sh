#!/bin/bash
# Oracle for cobalt-wharf: write the score_report.py program, then RUN it on the
# visible fixtures to produce /app/report.json. Never reads /tests.
set -eu

SOLVER="/app/score_report.py"
OUT="/app/report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import math
import sys


def is_valid(value):
    """A real number, but not a bool (booleans are invalid markers)."""
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def half_up(x, nd=3):
    return math.floor(x * (10 ** nd) + 0.5) / (10 ** nd)


def load(path):
    with open(path, "r", encoding="utf-8") as fh:
        obj = json.load(fh)
    if not isinstance(obj, dict):
        raise ValueError("input must be a JSON object: %s" % path)
    return obj


def reconcile(pred, key):
    rounds = {}
    tot_c = tot_t = 0
    for r in sorted(set(pred) | set(key)):
        p = pred.get(r, {})
        k = key.get(r, {})
        if not isinstance(p, dict) or not isinstance(k, dict):
            raise ValueError("round %r must map to an object" % r)
        c = t = 0
        for q, pv in p.items():
            if q not in k:
                continue  # unmatched: ignored entirely
            kv = k[q]
            if not is_valid(pv) or not is_valid(kv):
                continue  # invalid pair: dropped
            t += 1
            if pv == kv:
                c += 1
        acc = half_up(c / t) if t else None
        rounds[r] = {"correct": c, "total": t, "accuracy": acc}
        tot_c += c
        tot_t += t
    totals = {
        "correct": tot_c,
        "total": tot_t,
        "accuracy": half_up(tot_c / tot_t) if tot_t else None,
    }
    return {"rounds": rounds, "totals": totals}


def main():
    if len(sys.argv) != 4:
        print("usage: score_report.py <predictions_json> <answer_key_json> "
              "<output_json>", file=sys.stderr)
        sys.exit(2)
    pred = load(sys.argv[1])
    key = load(sys.argv[2])
    report = reconcile(pred, key)
    with open(sys.argv[3], "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the output.
python3 "$SOLVER" /app/predictions.json /app/answer_key.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
