#!/bin/bash
# Verifier for copper-thicket: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app fixtures, and
# EXECUTES the deliverable program (/app/reconcile.py) on the visible case and
# on every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_CRM_SHA="a37e6d47ecc0efad383442da342fab7b7f9300219d02b7394e839f97e5dd416c"
PRISTINE_BILL_SHA="9a02986cd74cc3af832177dcca60e4754831c624d4eab71c53669c5e969d511c"

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
if [ ! -f /app/billing_export.json ]; then
    echo "no-modify: /app/billing_export.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/billing_export.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_BILL_SHA" ]; then
        echo "no-modify: /app/billing_export.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/reconcile.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Normalize a report so it compares by content regardless of key order."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"total_conflicts", "conflicts"}, sorted(obj.keys())
    conflicts = obj["conflicts"]
    assert isinstance(conflicts, list), conflicts
    assert obj["total_conflicts"] == len(conflicts), (
        obj["total_conflicts"], len(conflicts))
    out = []
    for c in conflicts:
        assert isinstance(c, dict), c
        assert set(c.keys()) == {"user", "field", "values", "winner",
                                 "winner_source"}, sorted(c.keys())
        values = c["values"]
        assert isinstance(values, list) and len(values) == 2, values
        vnorm = []
        for v in values:
            assert isinstance(v, dict) and set(v.keys()) == {"system", "value"}, v
            vnorm.append((v["system"], v["value"]))
        assert vnorm[0][0] == "crm" and vnorm[1][0] == "billing", vnorm
        out.append((c["user"], c["field"], vnorm, c["winner"],
                    c["winner_source"]))
    return (obj["total_conflicts"], out)


def run_case(crm, billing, expected_path):
    out = "/tmp/copper_thicket_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, crm, billing, out],
        capture_output=True, text=True, timeout=120,
    )
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
    failures.append("visible fixtures modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/reconcile.py")
else:
    # --- visible case: EXECUTE reconcile.py on the live supplied fixtures ---
    if not (os.path.isfile("/app/crm_export.json")
            and os.path.isfile("/app/billing_export.json")):
        failures.append("visible fixtures missing")
    elif not run_case("/app/crm_export.json", "/app/billing_export.json",
                      "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/conflict_report.json must exist and ---
    # --- match the expected report for the visible fixtures ---
    if os.path.isfile("/app/conflict_report.json"):
        try:
            with open("/app/conflict_report.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("conflict_report.json does not match visible "
                                "expected")
        except Exception:
            failures.append("conflict_report.json unreadable")
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
            billing = os.path.join(base, "billing.json")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (crm, billing, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(crm, billing, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
