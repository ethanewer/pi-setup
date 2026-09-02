#!/bin/bash
# Verifier for cobalt-fjord: checks the visible-case deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app input, and EXECUTES
# the deliverable program (/app/solve.py) on the visible case and on every hidden
# case in /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture in /app (the instruction tells
# the agent not to modify it; tampering defeats the visible-case check).
PRISTINE_LOG_SHA="259ab60a02b1399a7e4b4138bcdfcc5a687bb764976d6b30c7ac1f4ffb4f9c5e"

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

TOP_KEYS = {"total_requests", "malformed", "status_classes", "error_rate_pct",
            "avg_latency_ms", "p95_latency_ms", "bytes_total",
            "unique_clients", "endpoints", "health"}


def norm(obj):
    """Normalize so floats compare at 4 decimals and dicts compare by content."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == TOP_KEYS, sorted(obj.keys())
    out = {}
    for k in ("total_requests", "malformed", "bytes_total", "unique_clients"):
        out[k] = int(obj[k])
    classes = obj["status_classes"]
    assert isinstance(classes, dict) and set(classes) == {"1xx", "2xx", "3xx", "4xx", "5xx"}
    out["status_classes"] = {c: int(classes[c]) for c in sorted(classes)}
    for k in ("error_rate_pct", "avg_latency_ms", "p95_latency_ms"):
        v = obj[k]
        assert v is None or isinstance(v, (int, float)), (k, v)
        out[k] = None if v is None else round(float(v), 4)
    eps = obj["endpoints"]
    assert isinstance(eps, dict), eps
    norm_eps = {}
    for p, v in eps.items():
        assert isinstance(v, dict) and set(v) == {"count", "avg_ms"}, (p, v)
        norm_eps[p] = {"count": int(v["count"]), "avg_ms": round(float(v["avg_ms"]), 4)}
    out["endpoints"] = norm_eps
    assert obj["health"] in ("healthy", "degraded", "critical", "unknown")
    out["health"] = obj["health"]
    return out


def run_case(log, expected_path):
    out = "/tmp/cobalt_fjord_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, log, out],
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
    failures.append("visible input modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible case: EXECUTE solve.py on the live supplied input ---
    if not os.path.isfile("/app/access.log"):
        failures.append("visible input missing")
    elif not run_case("/app/access.log", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/answer.json must exist and match ---
    if os.path.isfile("/app/answer.json"):
        try:
            with open("/app/answer.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("answer.json does not match visible expected")
        except Exception:
            failures.append("answer.json unreadable")
    else:
        failures.append("missing /app/answer.json")

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
            if not (os.path.isfile(log) and os.path.isfile(exp)):
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
