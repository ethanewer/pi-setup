#!/bin/bash
# Verifier for cinder-reach: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app input, and
# EXECUTES the deliverable program (/app/solve.py) on the visible case and on
# every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture (the instruction tells the
# agent not to modify it; tampering defeats the visible-case check).
PRISTINE_LOG_SHA="f12e01690a9e926993053aa87697227fa9464fe2c0be9d91db36f280b3ee7ae3"

no_modify_broken=0
if [ ! -f /app/access.log ]; then
    echo "no-modify: /app/access.log missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/access.log | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_LOG_SHA" ]; then
        echo "no-modify: /app/access.log was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])

KEY_ORDER = ["total_requests", "malformed", "status_classes", "error_rate",
             "avg_latency_ms", "p95_latency_ms", "bytes_total", "top_client"]


def norm(obj):
    """Normalize a report: enforce exact key set/order-independent content,
    round floats for comparison, guard all parses."""
    assert isinstance(obj, dict), "report is not a JSON object"
    assert list(obj.keys()) == KEY_ORDER, obj.keys()
    total = obj["total_requests"]
    malformed = obj["malformed"]
    assert isinstance(total, int) and total >= 0, total
    assert isinstance(malformed, int) and malformed >= 0, malformed
    classes = obj["status_classes"]
    assert isinstance(classes, dict) and list(classes.keys()) == [
        "1xx", "2xx", "3xx", "4xx", "5xx"], classes
    classes = {k: int(v) for k, v in classes.items()}
    nulls_ok = (total == 0)
    rate = obj["error_rate"]
    avg = obj["avg_latency_ms"]
    p95 = obj["p95_latency_ms"]
    top = obj["top_client"]
    if nulls_ok:
        assert rate is None and avg is None and p95 is None and top is None, obj
        rate = avg = p95 = top = None
    else:
        assert isinstance(rate, (int, float)), rate
        assert isinstance(avg, (int, float)), avg
        assert isinstance(p95, (int, float)), p95
        assert isinstance(top, str) and top, top
        rate = round(float(rate), 4)
        avg = round(float(avg), 4)
        p95 = round(float(p95), 4)
    bt = obj["bytes_total"]
    assert isinstance(bt, int) and bt >= 0, bt
    return (total, malformed, classes, rate, avg, p95, bt, top)


def run_case(log, expected_path):
    out = "/tmp/cinder_reach_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, log, out],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
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
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible case: EXECUTE solve.py on the live supplied input ---
    if not os.path.isfile("/app/access.log"):
        failures.append("visible input missing")
    elif not run_case("/app/access.log", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/stats.json must exist and match ---
    if os.path.isfile("/app/stats.json"):
        try:
            with open("/app/stats.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("stats.json does not match visible expected")
        except Exception:
            failures.append("stats.json unreadable")
    else:
        failures.append("missing /app/stats.json")

    # --- hidden cases: GENUINELY distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            log = os.path.join(base, "access.log")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (log, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(log, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
