#!/bin/bash
# Verifier for sorrel-marsh: checks the visible-case deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app input, and EXECUTES
# the deliverable program (/app/sync_report.py) on the visible case and on every
# hidden case in /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture in /app (the instruction tells
# the agent not to modify it; tampering defeats the visible-case check).
PRISTINE_INPUT_SHA="8cebd1b588eb610a2437119cc7a6d7c78d70d1b7c043841d925246f6842af63e"

no_modify_broken=0
if [ ! -f /app/contact_sync.json ]; then
    echo "no-modify: /app/contact_sync.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/contact_sync.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_INPUT_SHA" ]; then
        echo "no-modify: /app/contact_sync.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/sync_report.py"
no_modify_broken = int(sys.argv[1])


def norm(path):
    """Parse and structurally normalize a report; raise on any schema break."""
    with open(path) as f:
        obj = json.load(f)
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"users_affected", "total_conflicts", "conflicts"}, obj.keys()
    conflicts = obj["conflicts"]
    assert isinstance(conflicts, list)
    assert isinstance(obj["users_affected"], int) and isinstance(obj["total_conflicts"], int)
    # the total count must be consistent with the list length
    assert obj["total_conflicts"] == len(conflicts), (obj["total_conflicts"], len(conflicts))
    seen_users = set()
    normed = []
    for c in conflicts:
        assert isinstance(c, dict)
        assert set(c.keys()) == {"user", "field", "sources", "winner", "winner_device"}, c.keys()
        assert isinstance(c["user"], str) and isinstance(c["field"], str)
        seen_users.add(c["user"])
        assert isinstance(c["winner"], str) and isinstance(c["winner_device"], str)
        srcs = c["sources"]
        assert isinstance(srcs, list) and len(srcs) >= 2
        for s in srcs:
            assert isinstance(s, dict) and set(s.keys()) == {"device", "value", "synced_at"}, s
        assert any(s["value"] == c["winner"] and s["device"] == c["winner_device"] for s in srcs), c
        values = {s["value"] for s in srcs}
        assert len(values) >= 2, c  # every listed pair is a real conflict
        normed.append((c["user"], c["field"],
                       [(s["device"], s["value"], s["synced_at"]) for s in srcs],
                       c["winner"], c["winner_device"]))
    assert obj["users_affected"] == len(seen_users), (obj["users_affected"], seen_users)
    return tuple(normed)


def run_case(inp, expected_path):
    out = "/tmp/sorrel_marsh_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, inp, out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception:
        return False
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        return norm(out) == norm(expected_path)
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/sync_report.py")
else:
    # --- visible case: EXECUTE sync_report.py on the live supplied input ---
    if not os.path.isfile("/app/contact_sync.json"):
        failures.append("visible input missing")
    elif not run_case("/app/contact_sync.json", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/conflict_report.json must match ---
    if os.path.isfile("/app/conflict_report.json"):
        try:
            if norm("/app/conflict_report.json") != norm("/tests/expected.json"):
                failures.append("conflict_report.json does not match visible expected")
        except Exception:
            failures.append("conflict_report.json unreadable or malformed")
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
            inp = os.path.join(base, "input.json")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (inp, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(inp, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
