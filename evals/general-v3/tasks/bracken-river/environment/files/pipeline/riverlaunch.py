#!/usr/bin/env python3
"""Osprey Ridge flow-stats pipeline launcher.

Reads the R interpreter path from settings.json ("rscript" field) and runs
the R stage (sampler.R) as a subprocess. Fails fast when the R runtime is
not wired up.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS = os.path.join(HERE, "settings.json")
SAMPLER = os.path.join(HERE, "sampler.R")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: riverlaunch.py <params-file> <output-file>", file=sys.stderr)
        return 2
    params_file, out_file = sys.argv[1], sys.argv[2]

    try:
        with open(SETTINGS, "r", encoding="utf-8") as fh:
            settings = json.load(fh)
    except Exception as exc:  # unreadable/invalid settings
        print("riverlaunch: cannot read %s: %s" % (SETTINGS, exc), file=sys.stderr)
        return 3
    rscript = settings.get("rscript", "")
    if not isinstance(rscript, str) or not rscript:
        print("riverlaunch: settings.json has no usable 'rscript' field", file=sys.stderr)
        return 3
    if not (os.path.isfile(rscript) and os.access(rscript, os.X_OK)):
        print("riverlaunch: rscript %r is not an existing executable" % rscript, file=sys.stderr)
        return 3

    proc = subprocess.run(
        [rscript, "--vanilla", SAMPLER, params_file, out_file],
        capture_output=True,
        text=True,
        timeout=120,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        print("riverlaunch: R stage failed (exit %d)" % proc.returncode, file=sys.stderr)
        return 4
    if not os.path.isfile(out_file):
        print("riverlaunch: R stage produced no output file", file=sys.stderr)
        return 4
    print("RIVERLAUNCH_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
