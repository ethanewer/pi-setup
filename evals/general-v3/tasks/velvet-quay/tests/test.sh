#!/bin/bash
# Verifier for velvet-quay: ENFORCES the no-modify rule on the supplied /app
# fixtures and EXECUTES the deliverable (/app/audit.py) on the visible case and
# on every hidden ledger under /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_LEDGER_SHA="e073304d1448b6c92f522b471c5359ba28f87f52e29392e64e7101d170974a63"
PRISTINE_AUDIT_SHA="7e625c503091f9f09ad76f8783363b34b0f3a92925bf0a9361fa3d322e65a956"

no_modify_broken=0
if [ ! -f /app/charters.jsonl ]; then
    echo "no-modify: /app/charters.jsonl missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/charters.jsonl | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_LEDGER_SHA" ]; then
        echo "no-modify: /app/charters.jsonl was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/audit.txt ]; then
    echo "no-modify: /app/audit.txt missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/audit.txt | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_AUDIT_SHA" ]; then
        echo "no-modify: /app/audit.txt was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

AUDIT = "/app/audit.py"
no_modify_broken = int(sys.argv[1])
failures = []


def norm(obj):
    assert isinstance(obj, dict), "output is not an object"
    keys = {"as_of", "active_ids", "active_count", "pending_ids",
            "open_ended_ids", "by_vessel", "malformed"}
    if set(obj.keys()) != keys:
        raise ValueError("keys %r != %r" % (sorted(obj.keys()), sorted(keys)))
    for k in ("active_ids", "pending_ids", "open_ended_ids"):
        if not isinstance(obj[k], list) or obj[k] != sorted(obj[k]):
            raise ValueError("%s not a sorted list" % k)
    if obj["active_count"] != len(obj["active_ids"]):
        raise ValueError("active_count mismatch")
    if not isinstance(obj["by_vessel"], dict):
        raise ValueError("by_vessel not an object")
    if list(obj["by_vessel"].keys()) != sorted(obj["by_vessel"].keys()):
        raise ValueError("by_vessel keys not sorted")
    if not isinstance(obj["malformed"], int):
        raise ValueError("malformed not an int")
    return json.dumps(obj, sort_keys=True)


def run_case(ledger, audit_txt, expected_path, label):
    out = "/tmp/vq_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, AUDIT, ledger, audit_txt, out],
                           capture_output=True, text=True, timeout=120)
    except Exception as e:
        failures.append("%s: audit.py crashed: %r" % (label, e))
        return
    if r.returncode != 0 or not os.path.exists(out):
        failures.append("%s: audit.py exited %d" % (label, r.returncode))
        return
    try:
        with open(out) as f:
            got = norm(json.load(f))
        with open(expected_path) as f:
            want = norm(json.load(f))
    except Exception as e:
        failures.append("%s: output unreadable/invalid: %r" % (label, e))
        return
    if got != want:
        failures.append("%s: output mismatch" % label)


if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(AUDIT):
    failures.append("missing /app/audit.py")
else:
    # visible case: execute on the live supplied inputs
    if not (os.path.isfile("/app/charters.jsonl") and os.path.isfile("/app/audit.txt")):
        failures.append("visible inputs missing")
    elif not os.path.isfile("/tests/expected.json"):
        failures.append("visible expected missing")
    else:
        run_case("/app/charters.jsonl", "/app/audit.txt", "/tests/expected.json", "visible")

    # visible deliverable /app/audit.json must match the visible expected
    try:
        with open("/app/audit.json") as f:
            got = norm(json.load(f))
        with open("/tests/expected.json") as f:
            want = norm(json.load(f))
        if got != want:
            failures.append("deliverable /app/audit.json does not match expected")
    except Exception as e:
        failures.append("/app/audit.json unreadable/invalid: %r" % (e,))

    # hidden cases
    hidden_dir = "/tests/hidden"
    cases = []
    if os.path.isdir(hidden_dir):
        for d in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, d)
            if all(os.path.isfile(os.path.join(base, f))
                   for f in ("charters.jsonl", "audit.txt", "expected.json")):
                cases.append((d, base))
    if not cases:
        failures.append("no hidden cases present")
    for name, base in cases:
        run_case(os.path.join(base, "charters.jsonl"),
                 os.path.join(base, "audit.txt"),
                 os.path.join(base, "expected.json"), name)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ] && [ "$no_modify_broken" -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
