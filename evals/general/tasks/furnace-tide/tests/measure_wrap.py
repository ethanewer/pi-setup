#!/usr/bin/env python3
"""Measure the scorer's peak resident memory (VmHWM) by launching exactly one
score_traces.py child (exec'd directly, no shell) and polling
/proc/<pid>/status. Runs as a small dedicated process so the (much bigger)
verifier's resident set never pollutes the figure.

Usage: measure_wrap.py <python> /app/score_traces.py <input.csv> <out.txt>
Prints one line:  MEAS <returncode> <peak_kb> <wall_seconds>
"""
import subprocess
import sys
import time

cmd = sys.argv[1:]
p = subprocess.Popen(cmd)
peak = 0
t0 = time.monotonic()
while True:
    try:
        with open("/proc/%d/status" % p.pid) as fh:
            for line in fh:
                if line.lstrip().startswith("VmHWM:"):
                    peak = max(peak, int(line.split()[1]))
    except (FileNotFoundError, ProcessLookupError):
        pass
    if p.poll() is not None:
        break
    if time.monotonic() - t0 > 200.0:
        p.kill()
        break
    time.sleep(0.02)
rc = p.wait()
print("MEAS", rc, peak, round(time.monotonic() - t0, 2))
