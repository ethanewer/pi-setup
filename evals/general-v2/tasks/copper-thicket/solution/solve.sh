#!/bin/bash
# Oracle for copper-thicket: write the reconcile.py program, then RUN it on the
# visible fixtures to produce /app/conflict_report.json. Never reads /tests.
set -eu

SOLVER="/app/reconcile.py"
OUT="/app/conflict_report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import sys

FIELDS = ["email", "phone", "title", "department", "manager"]
CRM_WINS = {"title", "department", "manager"}


def present(value):
    """A value is present when it is a non-empty string after trimming."""
    if not isinstance(value, str):
        return None
    trimmed = value.strip()
    if trimmed == "":
        return None
    return trimmed


def load(path):
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise SystemExit("input root must be a JSON object")
    return data


def main():
    crm_path, billing_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    crm = load(crm_path)
    billing = load(billing_path)

    conflicts = []
    for user in sorted(set(crm) | set(billing)):
        crec = crm.get(user)
        brec = billing.get(user)
        crec = crec if isinstance(crec, dict) else {}
        brec = brec if isinstance(brec, dict) else {}
        for field in FIELDS:
            cv = present(crec.get(field))
            bv = present(brec.get(field))
            if cv is None or bv is None or cv == bv:
                continue
            if field in CRM_WINS:
                winner, winner_source = cv, "crm"
            else:
                winner, winner_source = bv, "billing"
            conflicts.append({
                "user": user,
                "field": field,
                "values": [
                    {"system": "crm", "value": cv},
                    {"system": "billing", "value": bv},
                ],
                "winner": winner,
                "winner_source": winner_source,
            })

    report = {"total_conflicts": len(conflicts), "conflicts": conflicts}
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the report.
python3 "$SOLVER" /app/crm_export.json /app/billing_export.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
