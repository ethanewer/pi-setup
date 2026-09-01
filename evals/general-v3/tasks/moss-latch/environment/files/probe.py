#!/usr/bin/env python3
"""Self-probe for the grainflow extension.

Usage: python3 /app/probe.py <out.json>

Imports the installed grainflow module, exercises it on the visible probe
points, and writes a JSON report. Do not modify this file: the grader re-runs
it verbatim.
"""
import json
import sys

import numpy

import grainflow


def main():
    out_path = sys.argv[1]
    report = {
        "numpy_major": int(numpy.__version__.split(".")[0]),
        "module_file": grainflow.__file__,
        "hann_8": [float(x) for x in grainflow.hann(8)],
        "hann_2": [float(x) for x in grainflow.hann(2)],
        "ramp_6": [float(x) for x in grainflow.ramp(6)],
        "ramp_0": [float(x) for x in grainflow.ramp(0)],
    }
    with open(out_path, "w") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
