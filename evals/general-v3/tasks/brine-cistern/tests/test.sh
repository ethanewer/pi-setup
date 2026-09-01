#!/bin/bash
# Verifier for brine-cistern: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app fixture, and
# EXECUTES the deliverable program (/app/merge_contacts.py) on the visible case
# and on every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture in /app (the instruction tells
# the agent not to modify it; tampering defeats the visible-case check).
PRISTINE_CSV_SHA="d0153fa3ff36e0a5e74673751e2818becab6da4939c8c2c26ae44ee96b2b7c6e"

no_modify_broken=0
if [ ! -f /app/contacts.csv ]; then
    echo "no-modify: /app/contacts.csv missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/contacts.csv | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CSV_SHA" ]; then
        echo "no-modify: /app/contacts.csv was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/merge_contacts.py"
no_modify_broken = int(sys.argv[1])


def run_case(csv_path, expected_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, csv_path, out_path],
            capture_output=True, text=True, timeout=120,
        )
    except Exception:
        return False
    if r.returncode != 0 or not os.path.exists(out_path):
        return False
    try:
        with open(out_path) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
    except Exception:
        return False
    # structural guards: exact key sets and a consistent total
    if not isinstance(got, dict) or set(got.keys()) != {"total_conflicts", "skipped", "users"}:
        return False
    if not isinstance(got["total_conflicts"], int) or not isinstance(got["skipped"], int):
        return False
    if not isinstance(got["users"], list):
        return False
    listed = sum(len(u.get("conflicts", [])) for u in got["users"])
    if got["total_conflicts"] != listed:
        return False
    return got == want


failures = []
if no_modify_broken:
    failures.append("visible fixture modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/merge_contacts.py")
else:
    # --- visible case: EXECUTE merge_contacts.py on the live supplied input ---
    if not os.path.isfile("/app/contacts.csv"):
        failures.append("visible input missing")
    elif not run_case("/app/contacts.csv", "/tests/expected.json",
                      "/tmp/brine_cistern_verify_out.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/merge_report.json must exist and match ---
    if os.path.isfile("/app/merge_report.json"):
        try:
            with open("/app/merge_report.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if got != want:
                failures.append("merge_report.json does not match visible expected")
        except Exception:
            failures.append("merge_report.json unreadable")
    else:
        failures.append("missing /app/merge_report.json")

    # --- hidden cases: GENUINELY distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            csv = os.path.join(base, "contacts.csv")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (csv, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(csv, exp, "/tmp/brine_cistern_verify_out_%s.json" % c):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
