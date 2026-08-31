#!/usr/bin/env python3
"""Measure a scorer child's peak resident memory (VmHWM) by launching exactly
one scorer child and polling /proc/<pid>/status. Runs as a small dedicated
process so the (much bigger) verifier's resident set never pollutes the figure.

Usage: python3 /tests/bag_wrap.py <bag.csv> <out.txt> <scorer.py>
Prints one line:  MEAS <returncode> <peak_kb> <wall_seconds>
"""
import subprocess
import sys
import time

bag, out, script = sys.argv[1], sys.argv[2], sys.argv[3]
p = subprocess.Popen(["python3", script, bag, out])
peak = 0
t0 = time.monotonic()
while True:
    try:
        with open("/proc/%d/status" % p.pid) as fh:
            for line in fh:
                if line.lstrip().startswith("VmHWM:"):
                    peak = max(peak, int(line.split()[1]))
    except FileNotFoundError:
        pass
    if p.poll() is not None:
        break
    if time.monotonic() - t0 > 180.0:
        p.kill()
        break
    time.sleep(0.02)
rc = p.wait()
print("MEAS", rc, peak, round(time.monotonic() - t0, 2))
