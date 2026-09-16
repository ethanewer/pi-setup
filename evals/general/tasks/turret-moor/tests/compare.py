#!/usr/bin/env python3
"""Compare the agent's JSON output against an independently computed
expectation.  Strict on the exact key set; floats compared with relative
tolerance; cell_count compared exactly.

Usage: compare.py <truth-json-string> <got-path> <rtol>
Exit 0 on match, 1 otherwise (with a readable message on stderr).
"""

import json
import math
import sys

KEYS = ("total_mass_g", "mass_weighted_temperature_K", "cell_count")


def main():
    truth = json.loads(sys.argv[1])
    got_path = sys.argv[2]
    rtol = float(sys.argv[3])

    try:
        with open(got_path) as f:
            got = json.load(f)
    except Exception as exc:  # noqa: BLE001
        print(f"cannot read output JSON: {exc}", file=sys.stderr)
        return 1

    if set(got.keys()) != set(KEYS):
        print(
            f"key set mismatch: expected {list(KEYS)}, got {sorted(got.keys())}",
            file=sys.stderr,
        )
        return 1

    for key in KEYS:
        if key not in truth:
            print(f"truth missing key {key}", file=sys.stderr)
            return 1

    if truth["cell_count"] != got["cell_count"]:
        print(
            f"cell_count mismatch: expected {truth['cell_count']}, got {got['cell_count']}",
            file=sys.stderr,
        )
        return 1

    for key in ("total_mass_g", "mass_weighted_temperature_K"):
        expected = float(truth[key])
        try:
            actual = float(got[key])
        except (TypeError, ValueError):
            print(f"{key} is not a number in output", file=sys.stderr)
            return 1
        if not math.isfinite(expected) or not math.isfinite(actual):
            print(f"{key} not finite: expected={expected} got={actual}", file=sys.stderr)
            return 1
        tol = rtol * max(abs(expected), abs(actual))
        if abs(expected - actual) > tol:
            print(
                f"{key} mismatch: expected {expected:.9g}, got {actual:.9g} (rtol {rtol})",
                file=sys.stderr,
            )
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())