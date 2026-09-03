#!/bin/bash
# Verifier for ds-runner-shard: EXECUTES the deliverable
# /app/harness/runner.py on the visible suite (/app/suites/visible.json) using
# the k/bail recorded in the delivered /app/run_report/params.json, requires
# the regenerated reports to equal the delivered ones, and runs hidden suites
# (uneven durations, cross-shard dep chains, all-fail, all-pass, K > cases,
# duration ties) under several k/bail combinations, independently recomputing
# LPT shard assignments, bail cascades and every report file. Writes reward to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

python3 - <<'PY'
import json, os, shutil, subprocess, sys

RUNNER = "/app/harness/runner.py"
VISIBLE = "/app/suites/visible.json"
DELIVERED = "/app/run_report"
HIDDEN = "/tests/hidden/suites"

failures = []

def run_runner(suite, outdir, k, bail, timeout=60):
    cmd = ["python3", RUNNER, "--suite", suite, "--out", outdir, "--k", str(k)]
    if bail:
        cmd.append("--bail")
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return proc, None
    except Exception as exc:
        return None, "runner invocation raised %s" % exc

def load_json(path, label):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        failures.append("%s unreadable/invalid JSON: %s" % (label, exc))
        return None

# ---------------------------------------------------------------------------
# Independent reference: recomputes LPT shard assignments, the bail cascade,
# and every report file from the suite manifest alone.
# ---------------------------------------------------------------------------
REF_FRAMEWORK = {"name": "mini-runner", "version": "2.0.0"}

def ref_partition(suite, k):
    """LPT: (-duration_ms, id) order into lowest-load bin, lowest index on tie."""
    ordered = sorted(suite["cases"], key=lambda c: (-c["duration_ms"], c["id"]))
    load = [0] * k
    shard = {}
    for c in ordered:
        b = min(range(k), key=lambda i: (load[i], i))
        shard[c["id"]] = b
        load[b] += c["duration_ms"]
    # members in manifest order (the run order within a launcher)
    members = [[c["id"] for c in suite["cases"] if shard[c["id"]] == i]
               for i in range(k)]
    return shard, members, load

def ref_simulate(suite, k, bail):
    shard, members, load = ref_partition(suite, k)
    status, skip_reason, ms = {}, {}, {}
    launcher_bailed = [False] * k
    for c in suite["cases"]:
        cid = c["id"]
        deps = c.get("deps", [])
        dep_blocked = any(status.get(d) != "passed" for d in deps)
        if dep_blocked:
            status[cid], skip_reason[cid], ms[cid] = "skipped", "dep", 0
        elif bail and launcher_bailed[shard[cid]]:
            status[cid], skip_reason[cid], ms[cid] = "skipped", "bail", 0
        else:
            ms[cid] = c["duration_ms"] if cid in shard else 0
            if c.get("fail", False):
                status[cid], skip_reason[cid] = "failed", None
                if bail:
                    launcher_bailed[shard[cid]] = True
            else:
                status[cid], skip_reason[cid] = "passed", None
    return shard, members, load, status, skip_reason, ms, launcher_bailed

def ref_reports(suite, k, bail):
    shard, members, load, status, skip_reason, ms, bailed = ref_simulate(suite, k, bail)
    results = []
    for c in suite["cases"]:
        cid = c["id"]
        results.append({
            "id": cid,
            "launcher": c["launcher"],
            "shard": shard[cid],
            "status": status[cid],
            "duration_ms": ms[cid],
            "deps": list(c.get("deps", [])),
            "skip_reason": skip_reason[cid],
        })
    counts = {"passed": 0, "failed": 0, "skipped": 0}
    for r in results:
        counts[r["status"]] += 1
    report = {
        "schemaVersion": "2.1",
        "framework": dict(REF_FRAMEWORK),
        "suite": suite["name"],
        "k": k,
        "bail": bail,
        "toolRun": {
            "numTotalTestCases": len(results),
            "numPassedTests": counts["passed"],
            "numFailedTests": counts["failed"],
            "numSkippedTests": counts["skipped"],
            "totalDurationMs": sum(r["duration_ms"] for r in results),
        },
        "results": results,
    }
    launchers = []
    for i in range(k):
        m = members[i]
        launchers.append({
            "launcher": i,
            "cases": list(m),
            "numPassed": sum(1 for cid in m if status[cid] == "passed"),
            "numFailed": sum(1 for cid in m if status[cid] == "failed"),
            "numSkipped": sum(1 for cid in m if status[cid] == "skipped"),
            "durationMs": sum(ms[cid] for cid in m),
            "nominalLoadMs": load[i],
            "bailed": bool(bailed[i]),
        })
    params = {"suite": suite["name"], "k": k, "bail": bail}
    return {"params.json": params, "report.json": report,
            **{"launcher-%d.json" % i: launchers[i] for i in range(k)}}

def expected_file_names(k):
    return ["params.json", "report.json"] + \
           ["launcher-%d.json" % i for i in range(k)]

def read_outdir(outdir, k):
    out = {}
    for name in expected_file_names(k):
        path = os.path.join(outdir, name)
        if not os.path.isfile(path):
            failures.append("missing output file %s" % path)
            continue
        out[name] = load_json(path, path)
    return out

def compare_case(label, got, want):
    for name in want:
        if name not in got or got[name] is None:
            continue
        if got[name] != want[name]:
            failures.append("%s: %s mismatch" % (label, name))

def check_run(suite_path, k, bail, label):
    outdir = "/tmp/dsrs_run"
    shutil.rmtree(outdir, ignore_errors=True)
    r = run_runner(suite_path, outdir, k, bail)
    if r is None:
        failures.append("%s: %s" % (label, "runner invocation failed"))
        return
    proc, err = r
    if proc is None:
        failures.append("%s: %s" % (label, err))
        return
    if proc.returncode != 0:
        failures.append("%s: runner exit code %s (stderr: %s)"
                        % (label, proc.returncode, (proc.stderr or "").strip()[:300]))
        return
    try:
        with open(suite_path, "r", encoding="utf-8") as fh:
            suite = json.load(fh)
    except Exception as exc:
        failures.append("%s: suite unreadable %s" % (label, exc))
        return
    got = read_outdir(outdir, k)
    want = ref_reports(suite, k, bail)
    compare_case(label, got, want)

# ---------------------------------------------------------------------------
# 1. Runner executable present.
# ---------------------------------------------------------------------------
if not os.path.isfile(RUNNER):
    failures.append("missing deliverable %s" % RUNNER)

# ---------------------------------------------------------------------------
# 2. Visible suite: rerun with delivered params and cross-check.
# ---------------------------------------------------------------------------
delivered_params = load_json(os.path.join(DELIVERED, "params.json"),
                             DELIVERED + "/params.json")
if delivered_params is None:
    failures.append("delivered run report has no readable params.json")
elif not isinstance(delivered_params, dict) or not isinstance(
        delivered_params.get("k"), int) or delivered_params.get("k") < 1 or \
        delivered_params.get("bail") not in (True, False):
    failures.append("delivered params.json must contain integer k >= 1 and bool bail")
else:
    k = delivered_params["k"]
    bail = delivered_params["bail"]
    check_run(VISIBLE, k, bail, "visible rerun")
    # The delivered report must equal the runner's own output.
    regen = read_outdir("/tmp/dsrs_run", k)
    delivered = read_outdir(DELIVERED, k)
    compare_case("delivered run_report", delivered, regen)

# ---------------------------------------------------------------------------
# 3. Hidden suites under several k/bail combinations.
# ---------------------------------------------------------------------------
COMBOS = {
    "uneven":  [(3, True), (3, False)],
    "chains":  [(2, True), (2, False)],
    "allfail": [(2, True), (2, False), (1, True)],
    "allpass": [(3, True), (1, True), (4, False)],
    "sparse":  [(5, True)],
    "ties":    [(2, True), (3, False)],
}
if not os.path.isdir(HIDDEN):
    failures.append("hidden suites directory missing")
else:
    names = sorted(os.listdir(HIDDEN))
    if not names:
        failures.append("no hidden suites present")
    for name in names:
        suite_path = os.path.join(HIDDEN, name, "suite.json")
        if not os.path.isfile(suite_path):
            failures.append("hidden suite '%s' has no suite.json" % name)
            continue
        for k, bail in COMBOS.get(name, [(2, True)]):
            check_run(suite_path, k, bail, "hidden '%s' k=%d bail=%s" % (name, k, bail))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then
  printf 1 > /logs/verifier/reward.txt
else
  printf 0 > /logs/verifier/reward.txt
fi
echo "ds-runner-shard verify rc=$rc reward=$(cat /logs/verifier/reward.txt)"
exit 0