#!/bin/bash
# Verifier for sable-heron: checks the visible-case deliverables, ENFORCES the
# no-modify rule on the supplied /app inputs, and EXECUTES the deliverable
# program (/app/merge_dirs.py) on the visible case and on every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_CRM_SHA="d69be9192bfcfa55cc6da4c73818c37358d187b0fefa7e31529e69cd9f8f00a7"
PRISTINE_PAYROLL_SHA="c19f26eee4878b16a1ac6627471ac07c8b047eae71e540116df810055c8e6cc4"

no_modify_broken=0
if [ ! -f /app/crm_export.json ]; then
    echo "no-modify: /app/crm_export.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/crm_export.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CRM_SHA" ]; then
        echo "no-modify: /app/crm_export.json was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/payroll_export.json ]; then
    echo "no-modify: /app/payroll_export.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/payroll_export.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_PAYROLL_SHA" ]; then
        echo "no-modify: /app/payroll_export.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/merge_dirs.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize a report so it compares by content regardless of key order."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"pairs_considered", "total_conflicts", "conflicts"}, set(obj.keys())
    conflicts = obj["conflicts"]
    assert isinstance(conflicts, list), conflicts
    assert isinstance(obj["total_conflicts"], int), obj["total_conflicts"]
    assert isinstance(obj["pairs_considered"], int), obj["pairs_considered"]
    # total_conflicts must be consistent with the list length
    assert obj["total_conflicts"] == len(conflicts), "total_conflicts != len(conflicts)"
    normed = []
    for c in conflicts:
        assert isinstance(c, dict), c
        assert set(c.keys()) == {"user", "field", "entries", "winner", "winner_export"}, set(c.keys())
        entries = c["entries"]
        assert isinstance(entries, list) and len(entries) == 2, entries
        assert entries[0]["export"] == "crm" and entries[1]["export"] == "payroll", entries
        normed.append((
            c["user"], c["field"],
            (entries[0]["value"], entries[0]["synced_at"]),
            (entries[1]["value"], entries[1]["synced_at"]),
            c["winner"], c["winner_export"],
        ))
    # conflicts must be sorted by (user, field)
    keys = [(n[0], n[1]) for n in normed]
    assert keys == sorted(keys), "conflicts not sorted by (user, field)"
    return (obj["pairs_considered"], obj["total_conflicts"], normed)


def run_case(crm, payroll, expected_path):
    out = "/tmp/sable_heron_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, crm, payroll, out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception:
        return False
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        return norm(got) == norm(want)
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/merge_dirs.py")
else:
    # --- visible case: EXECUTE merge_dirs.py on the live supplied inputs ---
    if not (os.path.isfile("/app/crm_export.json") and os.path.isfile("/app/payroll_export.json")):
        failures.append("visible inputs missing")
    elif not run_case("/app/crm_export.json", "/app/payroll_export.json", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/conflict_report.json must match ---
    if os.path.isfile("/app/conflict_report.json"):
        try:
            with open("/app/conflict_report.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("conflict_report.json does not match visible expected")
        except Exception:
            failures.append("conflict_report.json unreadable or invalid JSON")
    else:
        failures.append("missing /app/conflict_report.json")

    # --- hidden cases: genuinely distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            crm = os.path.join(base, "crm.json")
            payroll = os.path.join(base, "payroll.json")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (crm, payroll, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(crm, payroll, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
