#!/bin/bash
# Verifier for glass-forge: checks the visible deliverables, ENFORCES the
# no-modify rule on /app/roster.json, and EXECUTES /app/reconcile.py on the
# visible case and on every hidden case in /tests/hidden. Writes REWARD (0/1)
# to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_ROSTER_SHA="59875fae1a53a1a2e927cd7f9fb9dbd6a63d4ad3ad49ed6fb7cf723ad45a0705"

no_modify_broken=0
if [ ! -f /app/roster.json ]; then
    echo "no-modify: /app/roster.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/roster.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_ROSTER_SHA" ]; then
        echo "no-modify: /app/roster.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/reconcile.py"
no_modify_broken = int(sys.argv[1])


def norm(obj):
    """Validate the report schema and normalize for comparison."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"total_conflicts", "conflicts"}, sorted(obj.keys())
    conflicts = obj["conflicts"]
    assert isinstance(conflicts, list)
    assert isinstance(obj["total_conflicts"], int)
    assert obj["total_conflicts"] == len(conflicts), "total != len(conflicts)"
    for c in conflicts:
        assert isinstance(c, dict)
        assert set(c.keys()) == {"user", "field", "sources", "winner"}, sorted(c.keys())
        assert isinstance(c["user"], str) and isinstance(c["field"], str)
        assert isinstance(c["winner"], str)
        assert isinstance(c["sources"], list) and c["sources"]
        for s in c["sources"]:
            assert isinstance(s, dict)
            assert set(s.keys()) == {"source", "value"}, sorted(s.keys())
            assert isinstance(s["source"], str) and isinstance(s["value"], str)
    return json.dumps({"total_conflicts": obj["total_conflicts"], "conflicts": conflicts}, sort_keys=True)


def run_case(records, expected_path):
    out = "/tmp/glass_forge_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, records, out],
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
    failures.append("visible roster modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/reconcile.py")
else:
    # --- visible case: EXECUTE reconcile.py on the live supplied input ---
    if not os.path.isfile("/app/roster.json"):
        failures.append("visible roster missing")
    elif not run_case("/app/roster.json", "/tests/expected.json"):
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
            records = os.path.join(base, "records.json")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (records, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(records, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
