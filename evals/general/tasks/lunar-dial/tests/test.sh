#!/bin/bash
# Verifier for lunar-dial: EXECUTES the deliverable /app/sonar.py on the
# visible station context and on every hidden context under /tests/hidden,
# checks the depth, the 28-call budget, and replays every logged probe against
# the instrument. Writes 1.0/0.0 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_GAUGE_SHA="5e0931313926cd4abd403188c8f6b3839e69d91c634c8e443a56d2744da19343"

python3 - "$PRISTINE_GAUGE_SHA" <<'PY'
import hashlib, json, os, subprocess, sys

SONAR = "/app/sonar.py"
GAUGE = "/app/bin/gauge"
BUDGET = 28
gauge_sha_at_build = sys.argv[1]

failures = []


def true_depth(ctx):
    """Independent recomputation of the depth derived from a station context."""
    with open(ctx, "rb") as fh:
        data = json.loads(fh.read())
    return (int(data["station"]) * 2654435761 + int(data["datum"]) * 40503) % 2999 + 1


def gauge(endpoint, k, ctx):
    r = subprocess.run([GAUGE, ctx, endpoint, str(k)],
                       capture_output=True, text=True, timeout=30)
    return r.stdout.strip()


def check_case(ctx, tag):
    depth_out = "/tmp/ld_depth_%s.txt" % tag
    probes_out = "/tmp/ld_probes_%s.json" % tag
    for p in (depth_out, probes_out):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run([sys.executable, SONAR, ctx, depth_out, probes_out],
                           capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        return "timed out"
    if r.returncode != 0:
        return "exit %d" % r.returncode
    want = true_depth(ctx)
    try:
        with open(depth_out) as fh:
            got = int(fh.read().strip())
    except Exception:
        return "depth output missing/unreadable"
    if got != want:
        return "depth %d != true depth %d" % (got, want)
    try:
        with open(probes_out) as fh:
            rep = json.load(fh)
        assert isinstance(rep, dict)
        answer = rep["answer"]
        calls = rep["calls"]
        budget = rep["budget"]
        probes = rep["probes"]
    except Exception:
        return "probes transcript missing/malformed"
    if answer != want:
        return "transcript answer %r != true depth %d" % (answer, want)
    if not isinstance(calls, int) or not isinstance(probes, list):
        return "calls/probes wrong types"
    if calls != len(probes):
        return "calls (%r) != len(probes) (%d)" % (calls, len(probes))
    if calls > BUDGET or budget != BUDGET:
        return "budget violation: calls=%r budget=%r" % (calls, budget)
    endpoints = set()
    for p in probes:
        try:
            ep = p["endpoint"]
            k = int(p["k"])
            reply = str(p["reply"])
        except Exception:
            return "malformed probe entry %r" % (p,)
        endpoints.add(ep)
        actual = gauge(ep, k, ctx)
        if actual != reply:
            return "probe replay mismatch: ep=%s k=%d logged=%r actual=%r" % (
                ep, k, reply, actual)
    if endpoints != {"wet", "core"}:
        return "transcript must use both endpoints, saw %s" % sorted(endpoints)
    return None


if os.path.isfile(GAUGE):
    cur = hashlib.sha256(open(GAUGE, "rb").read()).hexdigest()
    if cur != gauge_sha_at_build:
        failures.append("/app/bin/gauge was modified")
else:
    failures.append("missing /app/bin/gauge")

if not os.path.isfile(SONAR):
    failures.append("missing /app/sonar.py")
else:
    err = check_case("/app/fixtures/station.json", "vis")
    if err:
        failures.append("visible case: %s" % err)
    # visible deliverables produced by the agent on the shipped context
    try:
        with open("/app/depth.txt") as fh:
            if int(fh.read().strip()) != true_depth("/app/fixtures/station.json"):
                failures.append("/app/depth.txt does not hold the true visible depth")
    except Exception:
        failures.append("/app/depth.txt missing/unreadable")
    try:
        with open("/app/probes.json") as fh:
            if json.load(fh).get("answer") != true_depth("/app/fixtures/station.json"):
                failures.append("/app/probes.json answer wrong for visible context")
    except Exception:
        failures.append("/app/probes.json missing/malformed")

    hidden = "/tests/hidden"
    if not os.path.isdir(hidden) or not os.listdir(hidden):
        failures.append("no hidden cases present")
    for name in sorted(os.listdir(hidden)):
        ctx = os.path.join(hidden, name)
        if not os.path.isfile(ctx):
            failures.append("hidden '%s' is not a context file" % name)
            continue
        err = check_case(ctx, name)
        if err:
            failures.append("hidden '%s': %s" % (name, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
