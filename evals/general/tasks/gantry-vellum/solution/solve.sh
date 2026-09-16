#!/usr/bin/env bash
# gantry-vellum oracle.
#
# Installs the fixed enrichd checkout as the deliverable (/app/enrichd),
# proves the unit suite is still green, then drives the visible workload
# through the running service while sampling the process family RSS from
# /proc: the median RSS of the second half of the run must not exceed the
# first half by more than the sanity bound.  This is the same measurement
# the verifier performs.  Never reads /tests.
set -euo pipefail

# 1. Install the fixed checkout (the deliverable) and run its unit suite.
rm -rf /app/enrichd
cp -a /solution/enrichd /app/enrichd
cd /app/enrichd
python3 -m unittest discover -s tests -t . -q

# 2. Smoke: feed the visible workload through the service in batches,
#    sampling the process tree RSS from /proc between batches, and require
#    the memory profile to have stabilised (growth between the first and
#    second half of the run under a generous bound).
python3 - <<'PY'
import os
import re
import subprocess
import sys
import time

APP = "/app/enrichd"
WORK = APP + "/workloads/visible.jsonl"
BATCH = 40
PACE = 1.0
BOUND_MB = 14.0


def vm_rss_kb(pid):
    try:
        with open("/proc/%d/status" % pid, encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError, ValueError, OSError):
        pass
    return 0


def tree_rss_kb(pid):
    total = 0
    stack = [pid]
    seen = set()
    while stack:
        p = stack.pop()
        if p in seen:
            continue
        seen.add(p)
        total += vm_rss_kb(p)
        try:
            entries = os.listdir("/proc")
        except OSError:
            continue
        for name in entries:
            if not name.isdigit():
                continue
            try:
                with open("/proc/%s/status" % name, encoding="utf-8") as fh:
                    m = re.search(r"^PPid:\s+(\d+)", fh.read(), re.M)
            except OSError:
                continue
            if m and int(m.group(1)) == pid:
                stack.append(int(name))
    return total


def median(xs):
    s = sorted(xs)
    return (s[len(s) // 2] + s[(len(s) - 1) // 2]) / 2.0


with open(WORK, encoding="utf-8") as fh:
    events = [l for l in fh.read().splitlines() if l.strip()]
out = "/tmp/enrichd.smoke.jsonl"
proc = subprocess.Popen(
    [sys.executable, "-m", "enrichd", "process", "--output", out, "--flush-every", "4"],
    cwd=APP, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL)
samples = []
t0 = time.monotonic()
for i in range(0, len(events), BATCH):
    chunk = events[i:i + BATCH]
    proc.stdin.write(("\n".join(chunk) + "\n").encode("utf-8"))
    proc.stdin.flush()
    time.sleep(PACE)
    samples.append((time.monotonic() - t0, tree_rss_kb(proc.pid)))
proc.stdin.close()
rc = proc.wait(timeout=120)
if rc != 0:
    print("oracle smoke: service exited rc=%r" % rc, file=sys.stderr)
    sys.exit(1)
mid = (samples[0][0] + samples[-1][0]) / 2.0
first = [rss for t, rss in samples if t < mid]
second = [rss for t, rss in samples if t >= mid]
m1, m2 = median(first) / 1024.0, median(second) / 1024.0
growth = m2 - m1
print("oracle smoke: RSS median %.1f -> %.1f MB (growth %.1f MB, bound %.1f MB)"
      % (m1, m2, growth, BOUND_MB))
if growth > BOUND_MB:
    print("oracle smoke: memory did not stabilise", file=sys.stderr)
    sys.exit(1)
print("solve.sh done: fixed /app/enrichd installed and verified")
PY