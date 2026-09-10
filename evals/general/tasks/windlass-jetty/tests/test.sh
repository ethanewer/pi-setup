#!/usr/bin/env bash
# Verifier for windlass-jetty (executes-deliverable).
#
# Starts the agent's deliverable serve.sh (which must regenerate bindings,
# build the Go server and bring it up on the given port), then drives the
# running service with three hidden Python clients (legacy-shape, box-shape,
# envelope-shape) that recompute the documented receipt/route_code rules and
# assert exact echo semantics, including that the deprecated field is
# preserved verbatim. Reward is 1 iff every hidden client passes.
#
# Guarantee a reward on every exit path: without the guard below, a verifier
# that dies mid-flight would write nothing and produce an unscorable record.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

REPO=/app/windlass-dispatch
PORT=50444
FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

cleanup() {
  if [ -f "$REPO/.server.pid" ]; then
    PID=$(head -1 "$REPO/.server.pid" 2>/dev/null || true)
    if [ -n "${PID:-}" ]; then
      kill "$PID" 2>/dev/null || true
    fi
  fi
  pkill -f "windlass-server --port=$PORT" 2>/dev/null || true
  return 0
}
trap 'cleanup' EXIT

# ---- deliverable present? ---------------------------------------------------
if [ ! -f "$REPO/serve.sh" ]; then
  echo "missing deliverable /app/windlass-dispatch/serve.sh" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi
if [ ! -x "$REPO/serve.sh" ]; then
  echo "deliverable /app/windlass-dispatch/serve.sh is not executable" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

# ---- bring the service up via the deliverable -------------------------------
if ! timeout 540 bash "$REPO/serve.sh" "$PORT"; then
  echo "serve.sh exited non-zero (regeneration, build or startup failure)" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

# belt-and-suspenders: the port must accept TCP connections before we probe
python3 - "$PORT" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
deadline = time.time() + 120
while time.time() < deadline:
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=0.5)
        s.close()
        sys.exit(0)
    except OSError:
        time.sleep(0.25)
sys.exit(1)
PY
if [ $? -ne 0 ]; then
  echo "port $PORT never accepted connections" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

# ---- hidden generalization cases ---------------------------------------------
for case in H1 H2 H3; do
  out="$(timeout 180 python3 "/tests/hidden/$case/client.py" "$PORT" 2>&1)"
  rc=$?
  if [ -n "$out" ]; then echo "$out"; fi
  if [ "$rc" -ne 0 ]; then
    fail "hidden case $case failed (rc=$rc)"
  fi
done

# ---- reward -----------------------------------------------------------------
if [ "$FAILED" = 1 ]; then
  echo "0" > /logs/verifier/reward.txt
else
  echo "1" > /logs/verifier/reward.txt
fi
exit 0