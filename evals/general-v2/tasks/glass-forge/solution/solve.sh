#!/bin/bash
# Oracle for glass-forge: write the reconcile.py program, then RUN it on the
# visible fixture to produce /app/conflict_report.json. Never reads /tests.
set -eu

SOLVER="/app/reconcile.py"
OUT="/app/conflict_report.json"

cat > "$SOLVER" <<'PY'
import json
import sys

PRIORITY = {"directory": 3, "payroll": 2, "badge": 1}
KEYS = ("user", "field", "source", "value")


def load_records(path):
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    records = doc.get("records", [])
    assert isinstance(records, list)
    kept = []
    for rec in records:
        if not isinstance(rec, dict):
            continue
        if set(rec.keys()) != set(KEYS):
            continue
        if not all(isinstance(rec[k], str) for k in KEYS):
            continue
        if rec["source"] not in PRIORITY:
            continue
        kept.append(rec)
    return kept


def main():
    records_path, out_path = sys.argv[1], sys.argv[2]
    records = load_records(records_path)

    # group by (user, field), preserving file order of records
    groups = {}
    order = []
    for rec in records:
        pair = (rec["user"], rec["field"])
        if pair not in groups:
            groups[pair] = []
            order.append(pair)
        groups[pair].append(rec)

    conflicts = []
    for pair in order:
        recs = groups[pair]
        values = {r["value"] for r in recs}
        if len(values) < 2:
            continue
        top = max(PRIORITY[r["source"]] for r in recs)
        winner = None
        for r in recs:  # file order; later record with top source wins
            if PRIORITY[r["source"]] == top:
                winner = r["value"]
        sources = []
        seen = set()
        for r in recs:
            sv = (r["source"], r["value"])
            if sv not in seen:
                seen.add(sv)
                sources.append({"source": r["source"], "value": r["value"]})
        conflicts.append({
            "user": pair[0],
            "field": pair[1],
            "sources": sources,
            "winner": winner,
        })

    report = {"total_conflicts": len(conflicts), "conflicts": conflicts}
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/roster.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
