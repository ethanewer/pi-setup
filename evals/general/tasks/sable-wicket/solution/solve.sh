#!/bin/bash
# Oracle for sable-wicket: transcribe one correct fix request per audited
# finding (excerpts come from the shipped audit report), apply them once
# through the patchdeck applier, and leave the 5/5 log as the second
# deliverable. Never reads /tests.
set -eu

test -f /app/lib/wickkit.py
test -f /app/audit/findings.json
test -x /app/tools/patchdeck.py

mkdir -p /app/requests
rm -f /app/requests/*.json /app/requests/*.done 2>/dev/null || true
rm -f /app/tools/patchdeck.log

python3 - <<'PY'
import json

audit = json.load(open("/app/audit/findings.json"))
FIX = {
    "F-01": "    return cents // units",
    "F-02": "    if units >= 12:",
    "F-03": "    return round(1.5 + inches * 0.25, 2)",
    "F-04": "    return min(max(diameter, 1.0), 4.0)",
    "F-05": "    return list(range(n))",
}
for f in audit["findings"]:
    req = {
        "finding": f["id"],
        "file": f["file"],
        "line": f["line"],
        "old": f["excerpt"],
        "new": FIX[f["id"]],
    }
    with open("/app/requests/%s.json" % f["id"], "w", encoding="utf-8") as fh:
        json.dump(req, fh, indent=2)
print("wrote %d fix requests" % len(audit["findings"]))
PY

# One apply pass: exactly one attempt per finding, all must land APPLIED.
python3 /app/tools/patchdeck.py apply

echo "patchdeck log:"
cat /app/tools/patchdeck.log

# Sanity: the repaired library must pass the visible selfcheck.
python3 /app/selfcheck.py
