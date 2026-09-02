#!/bin/bash
# Real oracle for sable-heron: write the merge_dirs.py program, then RUN it on
# the visible fixtures to produce /app/conflict_report.json. Never reads /tests.
set -eu

SOLVER="/app/merge_dirs.py"
OUT="/app/conflict_report.json"

cat > "$SOLVER" <<'PY'
import json
import sys

DEFAULT_SYNCED = "0000-00-00"


def normalize(path):
    """Reduce one export to {(user, field): (value, synced_at)}."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return {}
    if not isinstance(data, list):
        return {}
    best = {}
    for item in data:
        if not isinstance(item, dict):
            continue
        user = item.get("user")
        field = item.get("field")
        value = item.get("value")
        synced = item.get("synced_at", DEFAULT_SYNCED)
        if not isinstance(user, str) or not isinstance(field, str):
            continue
        if not isinstance(value, str):
            continue
        if not isinstance(synced, str):
            synced = DEFAULT_SYNCED
        key = (user, field)
        # greatest synced_at wins; tie -> LAST occurrence in array order
        if key not in best or synced >= best[key][1]:
            best[key] = (value, synced)
    return best


def main():
    crm_path, payroll_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    crm = normalize(crm_path)
    payroll = normalize(payroll_path)

    pairs = set(crm) | set(payroll)
    conflicts = []
    for key in sorted(pairs):
        if key not in crm or key not in payroll:
            continue
        cv, cs = crm[key]
        pv, ps = payroll[key]
        if cv == pv:
            continue
        if cs > ps:
            winner, winner_export = cv, "crm"
        else:
            winner, winner_export = pv, "payroll"
        conflicts.append({
            "user": key[0],
            "field": key[1],
            "entries": [
                {"export": "crm", "value": cv, "synced_at": cs},
                {"export": "payroll", "value": pv, "synced_at": ps},
            ],
            "winner": winner,
            "winner_export": winner_export,
        })

    report = {
        "pairs_considered": len(pairs),
        "total_conflicts": len(conflicts),
        "conflicts": conflicts,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# Run the produced program on the visible fixtures to generate the report.
python3 "$SOLVER" /app/crm_export.json /app/payroll_export.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
