#!/usr/bin/env bash
# Oracle for juniper-notch. Authors the agent deliverables and RUNS the real
# pipeline: publishes the crafted job directive onto the (fresh, unauthenticated)
# MQ bus the relay worker consumes, and drives the survey-gate socket protocol.
# This oracle does its own real work and never reads /tests.
set -euo pipefail
cd /app

# ---- 1. Deliverable /app/q.py : the relay tool (injector + socket client) ----
install -m 0755 /solution/q.py /app/q.py

# ---- 2. Craft the task directive /app/job.json (per the worker's schema) ----
python3 - <<'PY'
import json
directive = {
    "job_id": "relay-batch-1803",
    "kind": "rebalance",
    "sector": "north",
    "payload": [3, 1, 4, 1, 5],
}
with open("/app/job.json", "w") as fh:
    json.dump(directive, fh)
PY

# ---- 3. Bring the relay bus and survey gate up on loopback ----
pkill -f "mosquitto -c /app/relay/broker.conf" 2>/dev/null || true
pkill -f "/app/relay/gate.py" 2>/dev/null || true
sleep 0.2
mosquitto -c /app/relay/broker.conf > /tmp/oracle_broker.log 2>&1 &
BROKER_PID=$!
python3 /app/relay/gate.py /app/relay/maps/default.json > /tmp/oracle_gate.log 2>&1 &
GATE_PID=$!
sleep 1.5

# ---- 4. Run the relay tool: publish job to bus, survey gate -> roundtrip.out -
python3 /app/q.py
test -f /app/roundtrip.out || { echo "missing roundtrip.out"; exit 1; }

# ---- 5. Prove a worker actually consumes the crafted job ----
rm -f /app/relay/applied/*.result.json
mkdir -p /app/relay/applied
python3 /app/relay/worker.py > /tmp/oracle_worker.log 2>&1 &
WORKER_PID=$!
python3 - <<'PY'
import json, os, time
job = json.load(open("/app/job.json"))
path = "/app/relay/applied/%s.result.json" % job["job_id"]
deadline = time.time() + 12
while time.time() < deadline:
    if os.path.exists(path):
        break
    time.sleep(0.4)
if not os.path.exists(path):
    print("ORACLE: job was not consumed by the worker", file=open("/tmp/oracle_worker.log","a"))
    raise SystemExit(1)
print("oracle: job consumed ->", open(path).read().strip())
PY

kill "$BROKER_PID" "$GATE_PID" "$WORKER_PID" 2>/dev/null || true
echo "oracle ok"
exit 0