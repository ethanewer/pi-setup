#!/bin/bash
# keelson-cairn oracle.
# Repairs the kedd daemon's shutdown path in /app/kedd:
#   - WorkerPool gains a real drain-and-stop (shutdown) so joinAll can return;
#   - Ticker gains an explicit stop request;
#   - ShutdownHook stops the pool and ticker BEFORE joining them and no longer
#     holds the journal mutex across the joins, so the drain completes and the
#     journal is closed only at quiescence.
# The fixed sources are applied to the shipped tree, the project is rebuilt,
# and solve.sh proves the repair end-to-end against the visible sample
# workload: READY, SIGTERM, exit within 20s, journal complete and ordered.
# Never reads /tests; never hardcodes expectations beyond the journal contract.
set -euo pipefail

KEDD=/app/kedd

cp /solution/kedd-fixed/src/cairn/WorkerPool.java "$KEDD/src/cairn/WorkerPool.java"
cp /solution/kedd-fixed/src/cairn/Ticker.java "$KEDD/src/cairn/Ticker.java"
cp /solution/kedd-fixed/src/cairn/ShutdownHook.java "$KEDD/src/cairn/ShutdownHook.java"
cp /solution/kedd-fixed/build.sh /app/kedd/build.sh
cp /solution/kedd-fixed/run.sh /app/kedd/run.sh
chmod +x /app/kedd/build.sh /app/kedd/run.sh

bash "$KEDD/build.sh"

echo "oracle: fixed shutdown path applied, project rebuilt"

python3 - <<'PY'
import hashlib
import os
import signal
import subprocess
import time

KEDD = "/app/kedd"
WORKLOAD = KEDD + "/workloads/sample/workload.txt"
run = ["bash", KEDD + "/run.sh", "--workload", WORKLOAD,
       "--journal", "/tmp/oracle-journal.txt",
       "--ready", "/tmp/oracle-ready.txt",
       "--state", "/tmp/oracle-state"]

# expected journal from the workload alone
events = []
with open(WORKLOAD, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        o, p, w = line.split(",")
        events.append((int(o), p, int(w)))
want = []
for o, p, w in events:
    d = hashlib.sha256(("%d:%s:%d" % (o, p, w)).encode("utf-8")).hexdigest()[:16]
    want.append("%d|%s|%s" % (o, p, d))

for path in ("/tmp/oracle-journal.txt", "/tmp/oracle-ready.txt"):
    if os.path.exists(path):
        os.remove(path)

proc = subprocess.Popen(run, stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL)
deadline = time.time() + 60
ready = False
while time.time() < deadline:
    if os.path.isfile("/tmp/oracle-ready.txt"):
        with open("/tmp/oracle-ready.txt", encoding="utf-8") as fh:
            if fh.read().startswith("READY"):
                ready = True
                break
    if proc.poll() is not None:
        break
    time.sleep(0.1)
if not ready:
    raise SystemExit("oracle: daemon never became ready")

time.sleep(0.8)
if proc.poll() is None:
    proc.send_signal(signal.SIGTERM)
else:
    raise SystemExit("oracle: daemon exited before SIGTERM")

t0 = time.time()
while time.time() - t0 < 20:
    if proc.poll() is not None:
        break
    time.sleep(0.25)
if proc.poll() is None:
    proc.kill()
    proc.wait()
    raise SystemExit("oracle: daemon did not exit within 20s of SIGTERM")
if proc.returncode not in (0, 143):
    raise SystemExit("oracle: daemon exited rc=%s" % proc.returncode)

with open("/tmp/oracle-journal.txt", encoding="utf-8") as fh:
    got = [l.rstrip("\n") for l in fh if l.strip()]
if got != want:
    raise SystemExit("oracle: journal mismatch: %d lines, expected %d"
                     % (len(got), len(want)))
print("oracle: daemon exited cleanly in %.1fs, journal complete and ordered"
      " (%d entries)" % (time.time() - t0, len(got)))
PY

echo "oracle: done - fixed sources in place, rebuild green, lifecycle proven"