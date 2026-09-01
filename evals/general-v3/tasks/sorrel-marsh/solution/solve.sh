#!/bin/bash
# Oracle for sorrel-marsh: write the sync_report.py program, then RUN it on the
# visible fixture to produce /app/conflict_report.json. Never reads /tests.
set -eu

SOLVER="/app/sync_report.py"
OUT="/app/conflict_report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import sys

PRIORITY = {"laptop": 0, "phone": 1, "tablet": 2}


def main():
    if len(sys.argv) != 3:
        print("usage: sync_report.py <input.json> <output.json>", file=sys.stderr)
        return 2
    in_path, out_path = sys.argv[1], sys.argv[2]

    with open(in_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    records = data.get("records", [])
    if not isinstance(records, list):
        records = []

    groups = {}
    order = []
    for rec in records:
        key = (rec["user"], rec["field"])
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(rec)

    conflicts = []
    users = set()
    for key in order:
        rows = groups[key]
        if len({r["value"] for r in rows}) < 2:
            continue
        users.add(key[0])
        # Winner: greatest synced_at, then device priority (laptop > phone >
        # tablet), then earliest position in the input file.
        best = max(
            range(len(rows)),
            key=lambda i: (rows[i]["synced_at"],
                           -PRIORITY.get(rows[i]["device"], 99),
                           -i),
        )
        conflicts.append({
            "user": key[0],
            "field": key[1],
            "sources": [
                {"device": r["device"], "value": r["value"],
                 "synced_at": r["synced_at"]}
                for r in rows
            ],
            "winner": rows[best]["value"],
            "winner_device": rows[best]["device"],
        })

    report = {
        "users_affected": len(users),
        "total_conflicts": len(conflicts),
        "conflicts": conflicts,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixture to generate the report.
python3 "$SOLVER" /app/contact_sync.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
