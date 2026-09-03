#!/bin/bash
# Oracle for glacier-basin: implement the v2 runner (LPT sharding, bail
# mode, CTRF-like reports) into /app/harness/runner.py and produce the
# visible-suite run report at /app/run_report. Operates purely on the image.
set -eu

cat > /app/harness/runner.py <<'PY'
#!/usr/bin/env python3
"""mini-runner v2: LPT duration sharding across K launcher bins, bail mode
with dependency-driven skip cascades, and CTRF-like reports.

Usage:
    python3 /app/harness/runner.py --suite <suite.json> --out <outdir> --k <K> [--bail]

Writes into <outdir>: params.json, report.json, launcher-0.json .. launcher-<K-1>.json.
"""
import json
import os
import sys

SCHEMA_VERSION = "2.1"
FRAMEWORK = {"name": "mini-runner", "version": "2.0.0"}


def die(msg):
    print("mini-runner error: %s" % msg, file=sys.stderr)
    sys.exit(1)


def write_json(obj, path):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=2, sort_keys=True)
        fh.write("\n")


def parse_args(argv):
    suite_path = outdir = None
    k = None
    bail = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--suite":
            i += 1
            if i >= len(argv):
                die("--suite requires a value")
            suite_path = argv[i]
        elif arg == "--out":
            i += 1
            if i >= len(argv):
                die("--out requires a value")
            outdir = argv[i]
        elif arg == "--k":
            i += 1
            if i >= len(argv):
                die("--k requires an integer value")
            try:
                k = int(argv[i])
            except ValueError:
                die("--k requires an integer value")
        elif arg == "--bail":
            bail = True
        else:
            die("unknown argument %r" % arg)
        i += 1
    if not suite_path or not outdir or k is None:
        die("usage: runner.py --suite <suite.json> --out <outdir> --k <K> [--bail]")
    if k < 1:
        die("--k must be a positive integer")
    return suite_path, outdir, k, bail


def load_suite(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            suite = json.load(fh)
    except (OSError, ValueError) as exc:
        die("cannot read suite %s: %s" % (path, exc))
    if not isinstance(suite, dict) or not isinstance(suite.get("cases"), list):
        die("suite must be a JSON object with a 'cases' list")
    if not isinstance(suite.get("name"), str) or not suite["name"]:
        die("suite must declare a non-empty string 'name'")
    cases = suite["cases"]
    seen = {}
    for case in cases:
        if not isinstance(case, dict):
            die("each case must be a JSON object")
        for field in ("id", "launcher", "duration_ms"):
            if field not in case:
                die("case missing field %r" % field)
        cid = case["id"]
        if not isinstance(cid, str) or not cid:
            die("case id must be a non-empty string")
        if cid in seen:
            die("duplicate case id %r" % cid)
        seen[cid] = True
        if not isinstance(case["launcher"], str) or not case["launcher"]:
            die("case %r has no launcher" % cid)
        if not isinstance(case["duration_ms"], int) or case["duration_ms"] < 1:
            die("case %r: duration_ms must be a positive integer" % cid)
        deps = case.get("deps", [])
        if not isinstance(deps, list) or not all(isinstance(d, str) for d in deps):
            die("case %r: deps must be a list of ids" % cid)
        if "fail" in case:
            if not isinstance(case["fail"], bool):
                die("case %r: fail must be a boolean" % cid)
    # deps must reference known ids and precede their dependents (topological).
    index = {c["id"]: i for i, c in enumerate(cases)}
    for idx, case in enumerate(cases):
        for d in case.get("deps", []):
            if d not in index:
                die("case %r depends on unknown case %r" % (case["id"], d))
            if index[d] >= idx:
                die("case %r: dependency %r must appear earlier in the manifest"
                    % (case["id"], d))
    return suite


def lpt_shards(suite, k):
    """LPT partition: (-duration_ms, id) order into lowest-load bin with
    lowest-index tie-break."""
    cases = suite["cases"]
    order = sorted(cases, key=lambda c: (-c["duration_ms"], c["id"]))
    loads = [0] * k
    shard = {}
    for c in order:
        bi = min(range(k), key=lambda i: (loads[i], i))
        shard[c["id"]] = bi
        loads[bi] += c["duration_ms"]
    # members listed in manifest order (the order a launcher runs them)
    members = [[c["id"] for c in cases if shard[c["id"]] == i] for i in range(k)]
    return shard, members, loads


def simulate(suite, k, bail):
    shard, members, loads = lpt_shards(suite, k)
    status, reason, dur = {}, {}, {}
    bailed = [False] * k
    cases = suite["cases"]
    for c in cases:
        cid = c["id"]
        bi = shard[cid]
        dep_blocked = any(status.get(d) != "passed" for d in c.get("deps", []))
        if dep_blocked:
            status[cid], reason[cid], dur[cid] = "skipped", "dep", 0
        elif bail and bailed[bi]:
            status[cid], reason[cid], dur[cid] = "skipped", "bail", 0
        else:
            dur[cid] = c["duration_ms"]
            if c.get("fail", False):
                status[cid], reason[cid] = "failed", None
                if bail:
                    bailed[bi] = True
            else:
                status[cid], reason[cid] = "passed", None
    return shard, members, loads, status, reason, dur, bailed


def build_reports(suite, k, bail, shard, members, loads, status, reason, dur,
                  bailed):
    cases = suite["cases"]
    results = []
    for c in cases:
        cid = c["id"]
        results.append({
            "id": cid,
            "launcher": c["launcher"],
            "shard": shard[cid],
            "status": status[cid],
            "duration_ms": dur[cid],
            "deps": list(c.get("deps", [])),
            "skip_reason": reason[cid],
        })
    n_passed = sum(1 for r in results if r["status"] == "passed")
    n_failed = sum(1 for r in results if r["status"] == "failed")
    n_skipped = sum(1 for r in results if r["status"] == "skipped")
    report = {
        "schemaVersion": SCHEMA_VERSION,
        "framework": dict(FRAMEWORK),
        "suite": suite["name"],
        "k": k,
        "bail": bail,
        "toolRun": {
            "numTotalTestCases": len(cases),
            "numPassedTests": n_passed,
            "numFailedTests": n_failed,
            "numSkippedTests": n_skipped,
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
            "durationMs": sum(dur[cid] for cid in m),
            "nominalLoadMs": loads[i],
            "bailed": bool(bailed[i]),
        })
    params = {"suite": suite["name"], "k": k, "bail": bail}
    return report, launchers, params


def main(argv):
    suite_path, outdir, k, bail = parse_args(argv)
    suite = load_suite(suite_path)
    shard, members, loads, status, reason, dur, bailed = simulate(suite, k, bail)
    report, launchers, params = build_reports(
        suite, k, bail, shard, members, loads, status, reason, dur, bailed)
    os.makedirs(outdir, exist_ok=True)
    write_json(params, os.path.join(outdir, "params.json"))
    write_json(report, os.path.join(outdir, "report.json"))
    for i in range(k):
        write_json(launchers[i], os.path.join(outdir, "launcher-%d.json" % i))
    tr = report["toolRun"]
    print("mini-runner v2: suite=%s k=%d bail=%s total=%d passed=%d failed=%d skipped=%d"
          % (suite["name"], k, bail, tr["numTotalTestCases"], tr["numPassedTests"],
             tr["numFailedTests"], tr["numSkippedTests"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY

chmod 0644 /app/harness/runner.py

# Produce the visible-suite run report (k=3, bail on).
python3 /app/harness/runner.py --suite /app/suites/visible.json --out /app/run_report --k 3 --bail

echo "solve.sh done"
ls -l /app/harness/runner.py
find /app/run_report -type f | sort
cat /app/run_report/params.json