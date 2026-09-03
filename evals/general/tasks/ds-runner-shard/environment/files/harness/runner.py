#!/usr/bin/env python3
"""mini-runner v1: minimal sequential test-runner scaffold.

The harness discovers test cases from a suite.json manifest and currently
runs every case in a single launcher, one after another, writing a flat
results file. Parallel launcher sharding, failure simulation and detailed
reporting are NOT implemented yet -- that is the extension work.

Usage:
    python3 /app/harness/runner.py <suite.json> <outdir>
"""
import json
import os
import sys

USAGE = "usage: python3 runner.py <suite.json> <outdir>"


def die(msg):
    print("error: %s" % msg, file=sys.stderr)
    sys.exit(1)


def main(argv):
    if len(argv) != 2:
        die(USAGE)
    suite_path, outdir = argv

    try:
        with open(suite_path, "r", encoding="utf-8") as fh:
            suite = json.load(fh)
    except (OSError, ValueError) as exc:
        die("cannot read suite %s: %s" % (suite_path, exc))

    if not isinstance(suite, dict) or not isinstance(suite.get("cases"), list):
        die("suite must be a JSON object with a 'cases' list")
    if not isinstance(suite.get("name"), str):
        die("suite must declare a string 'name'")

    seen = set()
    for case in suite["cases"]:
        for field in ("id", "launcher", "duration_ms"):
            if field not in case:
                die("case missing field '%s'" % field)
        if case["id"] in seen:
            die("duplicate case id '%s'" % case["id"])
        seen.add(case["id"])
        if not isinstance(case["duration_ms"], int) or case["duration_ms"] < 1:
            die("case '%s': duration_ms must be a positive integer" % case["id"])

    # v1: run every case through the single launcher bin, in manifest order.
    results = []
    for case in suite["cases"]:
        results.append({
            "id": case["id"],
            "launcher": case["launcher"],
            "duration_ms": case["duration_ms"],
            "status": "passed",
        })

    os.makedirs(outdir, exist_ok=True)
    flat = {
        "suite": suite["name"],
        "launchers": 1,
        "results": results,
    }
    out_path = os.path.join(outdir, "flat-results.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(flat, fh, indent=2, sort_keys=True)
        fh.write("\n")

    print("mini-runner v1: ran %d cases sequentially %s -> %s"
          % (len(results), suite["name"], out_path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))