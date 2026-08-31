#!/bin/bash
# Verifier for basalt-quay: checks the visible deliverables, ENFORCES the
# no-modify rule on the supplied /app fixtures, and EXECUTES the deliverable
# client (/app/solve.py) against the visible session and every hidden session
# in /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the checks).
PRISTINE_SERVICE_SHA="6a56a84f152e0e566bc8f531b38d1ba73d14a5a749d81b74f457efa81171bffd"
PRISTINE_CASE_SHA="b8e0d5826c4615519e508d018ffd1867612204725b3f7e76ece8f2673b25f100"

no_modify_broken=0
if [ ! -f /app/planner_service.py ]; then
    echo "no-modify: /app/planner_service.py missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/planner_service.py | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SERVICE_SHA" ]; then
        echo "no-modify: /app/planner_service.py was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/planner/visible_case.json ]; then
    echo "no-modify: /app/planner/visible_case.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/planner/visible_case.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CASE_SHA" ]; then
        echo "no-modify: /app/planner/visible_case.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys, time, urllib.request

SERVICE = "/app/planner_service.py"
SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])
failures = []
if no_modify_broken:
    failures.append("provided /app fixtures modified or missing (no-modify rule)")


def start_service(case, out, port):
    try:
        p = subprocess.Popen(
            [sys.executable, SERVICE, "--serve", "--port", str(port),
             "--case", case, "--out", out],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        return None
    for _ in range(100):
        if p.poll() is not None:
            return None
        try:
            with urllib.request.urlopen(
                    "http://127.0.0.1:%d/api/session" % port, timeout=2) as r:
                json.load(r)
            return p
        except Exception:
            time.sleep(0.1)
    try:
        p.kill()
    except Exception:
        pass
    return None


def load_expected(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert isinstance(data, dict) and isinstance(data.get("records"), list), path
    return data["records"]


def norm_records(path):
    """Parse a plans JSONL file strictly; returns list of records or None."""
    try:
        with open(path, "rb") as f:
            raw = f.read().decode("utf-8")
    except Exception:
        return None
    if not raw.endswith("\n"):
        return None
    recs = []
    for line in raw.split("\n")[:-1]:
        try:
            rec = json.loads(line)
        except Exception:
            return None
        if not isinstance(rec, dict) or set(rec.keys()) != {"id", "batch", "shape"}:
            return None
        shape = rec["shape"]
        if not isinstance(shape, dict) or set(shape.keys()) != {
                "vcpus", "memory_gib", "disk_gib"}:
            return None
        if any(type(v) is not int for v in shape.values()):
            return None
        recs.append({"id": rec["id"], "batch": rec["batch"], "shape": dict(shape)})
    return recs


def run_case(case_path, expected_path, port, tag):
    out = "/tmp/bq_service_out_%s.jsonl" % tag
    plans = "/tmp/bq_client_plans_%s.jsonl" % tag
    for p in (out, plans):
        if os.path.exists(p):
            os.remove(p)
    proc = start_service(case_path, out, port)
    if proc is None:
        return "service failed to start"
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, "--url",
             "http://127.0.0.1:%d" % port, "--out", plans],
            capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            return "client exited %d" % r.returncode
        want = load_expected(expected_path)
        for path, who in ((out, "service file"), (plans, "client file")):
            got = norm_records(path)
            if got is None:
                return "%s missing/invalid" % path
            if got != want:
                return "records mismatch (%s)" % who
        return None
    except Exception as e:
        return "exception: %s" % e
    finally:
        try:
            proc.kill()
            proc.wait(timeout=10)
        except Exception:
            pass


if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible case: run the client against a fresh service instance ---
    err = run_case("/app/planner/visible_case.json", "/tests/expected.json",
                   8731, "visible")
    if err:
        failures.append("visible case: %s" % err)

    # --- visible deliverable: /app/plans.jsonl must match the expected records ---
    if not os.path.isfile("/app/plans.jsonl"):
        failures.append("missing /app/plans.jsonl")
    else:
        want = load_expected("/tests/expected.json")
        got = norm_records("/app/plans.jsonl")
        if got is None:
            failures.append("/app/plans.jsonl unreadable or structurally invalid")
        elif got != want:
            failures.append("/app/plans.jsonl does not match visible expected records")

    # --- hidden cases: distinct portfolios on fresh service instances ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for i, c in enumerate(cases):
            base = os.path.join(hidden_dir, c)
            case = os.path.join(base, "case.json")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (case, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            err = run_case(case, exp, 8901 + i, c)
            if err:
                failures.append("hidden case '%s': %s" % (c, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
