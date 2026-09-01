#!/bin/bash
# Verifier for tarn-quay: EXECUTES the deliverable program (/app/merge.py) on
# the visible snapshots and on every hidden snapshots directory in
# /tests/hidden, checks /app/merged.json against the visible expected roster,
# and asserts types, ordering, uniqueness, and completeness with distinct
# checks. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/merge.py"
OUT = "/tmp/tarn_quay_verify_out.json"


def check_roster(got, expected, label, failures):
    """Distinct asserts: validity, types, count, ordering, uniqueness, content."""
    def fail(msg):
        failures.append("%s: %s" % (label, msg))

    if not isinstance(got, list):
        fail("roster is not a JSON array")
        return
    seen_ids = []
    for i, rec in enumerate(got):
        if not isinstance(rec, dict):
            fail("element %d is not an object" % i)
            continue
        if set(rec.keys()) != {"id", "name", "value"}:
            fail("element %d has wrong field set %r" % (i, sorted(rec.keys())))
            continue
        rid, name, value = rec["id"], rec["name"], rec["value"]
        if isinstance(rid, bool) or not isinstance(rid, int):
            fail("element %d id is not an integer" % i)
        if not isinstance(name, str):
            fail("element %d name is not a string" % i)
        if isinstance(value, bool) or not isinstance(value, int):
            fail("element %d value is not an integer" % i)
        seen_ids.append(rid)
    for a, b in zip(seen_ids, seen_ids[1:]):
        if not a < b:
            fail("ids not strictly ascending at %r -> %r (order/duplicates)" % (a, b))
            break
    if len(set(seen_ids)) != len(seen_ids):
        fail("duplicate ids present")
    # exact content comparison (intension: normalized rows, sorted)
    if json.loads(json.dumps(got)) != expected:
        fail("roster content/order mismatch vs expected")


def run_case(snapshots_dir, expected, label, failures):
    if os.path.exists(OUT):
        os.remove(OUT)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, snapshots_dir, OUT],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as e:
        failures.append("%s: merge.py crashed: %r" % (label, e))
        return
    if r.returncode != 0:
        failures.append("%s: merge.py rc=%s stderr=%r"
                        % (label, r.returncode, (r.stderr or "")[-200:]))
        return
    if not os.path.exists(OUT):
        failures.append("%s: no output written" % label)
        return
    try:
        with open(OUT) as f:
            got = json.load(f)
    except Exception as e:
        failures.append("%s: output not valid JSON: %r" % (label, e))
        return
    check_roster(got, expected, label, failures)


failures = []

if not os.path.isfile(SOLVE):
    failures.append("missing /app/merge.py")
else:
    # --- visible case: EXECUTE merge.py on the shipped snapshots ---
    if not os.path.isdir("/app/snapshots"):
        failures.append("visible snapshots dir missing")
    else:
        with open("/tests/expected.json") as f:
            visible_expected = json.load(f)
        run_case("/app/snapshots", visible_expected, "visible", failures)

    # --- visible-case deliverable: /app/merged.json must match too ---
    if os.path.isfile("/app/merged.json"):
        try:
            with open("/app/merged.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            check_roster(got, want, "merged.json", failures)
        except Exception as e:
            failures.append("merged.json unreadable: %r" % e)
    else:
        failures.append("missing /app/merged.json")

    # --- hidden cases: genuinely distinct snapshots with their own expecteds ---
    hidden_root = "/tests/hidden"
    if os.path.isdir(hidden_root):
        cases = sorted(d for d in os.listdir(hidden_root)
                       if os.path.isdir(os.path.join(hidden_root, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_root, c)
            snaps = os.path.join(base, "snapshots")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isdir(snaps) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            with open(exp) as f:
                expected = json.load(f)
            run_case(snaps, expected, "hidden:%s" % c, failures)
    else:
        failures.append("no /tests/hidden")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
