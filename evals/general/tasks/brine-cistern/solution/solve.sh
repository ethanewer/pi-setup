#!/bin/bash
# Oracle for brine-cistern: write the merge tool, then RUN it on the visible
# fixture to produce /app/merge_report.json. Never reads /tests.
set -eu

SOLVER="/app/merge_contacts.py"
OUT="/app/merge_report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import sys

PRIORITY = {"crm": 0, "billing": 1, "support": 2}


def main():
    if len(sys.argv) != 3:
        print("usage: merge_contacts.py <input_csv> <output_json>", file=sys.stderr)
        sys.exit(2)
    in_path, out_path = sys.argv[1], sys.argv[2]

    with open(in_path, "r", encoding="utf-8") as fh:
        lines = fh.read().splitlines()

    data = {}  # (user, field) -> {source: value}
    skipped = 0
    for idx, line in enumerate(lines):
        if idx == 0:
            continue  # header
        if line.strip() == "":
            continue  # blank lines ignored entirely
        parts = [p.strip() for p in line.split(",")]
        if len(parts) != 4 or not all(parts):
            skipped += 1
            continue
        user, field, source, value = parts
        if source not in PRIORITY:
            skipped += 1
            continue
        data.setdefault((user, field), {})[source] = value  # last occurrence wins

    per_user = {}
    for (user, field), srcs in data.items():
        if len(set(srcs.values())) < 2:
            continue  # single source or full agreement: not a conflict
        sources = [
            {"source": s, "value": srcs[s]}
            for s in sorted(srcs, key=lambda s: PRIORITY[s])
        ]
        winner = sources[0]["value"]
        per_user.setdefault(user, []).append(
            {"field": field, "sources": sources, "winner": winner}
        )

    users = [
        {"user": u, "conflicts": sorted(per_user[u], key=lambda c: c["field"])}
        for u in sorted(per_user)
    ]
    report = {
        "total_conflicts": sum(len(u["conflicts"]) for u in users),
        "skipped": skipped,
        "users": users,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixture to generate the report.
python3 "$SOLVER" /app/contacts.csv "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
