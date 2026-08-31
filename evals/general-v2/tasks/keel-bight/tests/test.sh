#!/bin/bash
# Verifier for keel-bight: enforces the no-modify rule on /app/requests.jsonl,
# checks the visible deliverables, EXECUTES /app/solve.py on the visible input
# and on every hidden case in /tests/hidden, and strictly deserializes every
# emitted plan record (exact key lists/order and JSON types). Writes REWARD
# (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture (the instruction forbids
# modifying it; tampering defeats the visible-case check).
PRISTINE_REQ_SHA="8367c257e92f864ae8f8ef31828b28de564b2bbd047064fe593f0e5898610717"

no_modify_broken=0
if [ ! -f /app/requests.jsonl ]; then
    echo "no-modify: /app/requests.jsonl missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/requests.jsonl | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_REQ_SHA" ]; then
        echo "no-modify: /app/requests.jsonl was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])


def parse_plans_file(path):
    """Strict deserialization: one compact plan record per line."""
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    plans = []
    for line in text.split("\n"):
        if line == "":
            continue
        obj = json.loads(line)
        assert list(obj.keys()) == ["id", "batch", "shape"], obj
        sh = obj["shape"]
        assert list(sh.keys()) == ["capacity", "days", "code", "vessel"], sh
        assert type(sh["capacity"]) is float, sh
        assert type(sh["days"]) is int, sh
        assert type(sh["code"]) is str and type(sh["vessel"]) is str, sh
        compact = json.dumps(obj, separators=(",", ":"))
        assert line == compact, (line, compact)
        plans.append(obj)
    return plans


def parse_summary_file(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    obj = json.loads(raw)
    assert list(obj.keys()) == ["requests", "plans", "rejected",
                                "expedited", "batches"], obj
    batches = obj["batches"]
    assert list(batches.keys()) == sorted(batches.keys()), batches
    canon = json.dumps(obj, indent=2) + "\n"
    assert raw == canon.encode("utf-8"), (raw, canon)
    return obj


def run_case(req_path, expected_path):
    plans_out = "/tmp/keel_bight_plans.jsonl"
    summary_out = "/tmp/keel_bight_verify_summary.json"
    for p in (plans_out, summary_out):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, req_path, plans_out, summary_out],
            capture_output=True, text=True, timeout=120,
        )
        if r.returncode != 0:
            return "nonzero exit"
        got_plans = parse_plans_file(plans_out)
        got_summary = parse_summary_file(summary_out)
        with open(expected_path) as fh:
            want = json.load(fh)
        if got_plans != want["plans"]:
            return "plan records differ"
        if got_summary != want["summary"]:
            return "summary mismatch"
    except Exception as e:
        return "exception: %r" % (e,)
    return None


failures = []
if no_modify_broken:
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    err = run_case("/app/requests.jsonl", "/tests/expected.json")
    if err:
        failures.append("visible run failed: %s" % err)

    # Visible-case deliverables must exist and match the visible expected.
    for path in ("/app/plans.jsonl", "/app/summary.json"):
        if not os.path.isfile(path):
            failures.append("missing %s" % path)

    if not failures:
        try:
            got_plans = parse_plans_file("/app/plans.jsonl")
            got_summary = parse_summary_file("/app/summary.json")
            with open("/tests/expected.json") as fh:
                want = json.load(fh)
            if got_plans != want["plans"]:
                failures.append("plans.jsonl does not match visible expected")
            if got_summary != want["summary"]:
                failures.append("summary.json does not match visible expected")
        except Exception:
            failures.append("visible deliverables fail strict deserialization")

    # Hidden cases
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            req = os.path.join(base, "requests.jsonl")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (req, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            err = run_case(req, exp)
            if err:
                failures.append("hidden case '%s': %s" % (c, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
