#!/bin/bash
# Verifier for item-061-hard. Starts the agent's server, runs the agent's client,
# and checks that its stdout is exactly "PING".
mkdir -p /logs/verifier

run_result=0
if [ -f /app/console_server.py ] && [ -f /app/console_client.py ]; then
  # Safety: terminate any stale server process to free the port.
  for old in $(ps aux | grep -F '/app/console_server.py' | awk '{print $2}'); do
    kill "$old" >/dev/null 2>&1
  done

  python3 /app/console_server.py >/tmp/verifier_srv.log 2>&1 &
  PID=$!

  # Wait (bounded) for the port to accept connections.
  ready=0
  for _ in $(seq 1 20); do
    if python3 - <<'PYCHECK' 2>/dev/null
import socket, sys
try:
    s = socket.create_connection(("127.0.0.1", 2323), timeout=0.5)
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
PYCHECK
    then
      ready=1
      break
    fi
    sleep 0.25
  done

  if [ "$ready" = "1" ]; then
    if python3 /app/console_client.py >/tmp/verifier_client.out 2>/tmp/verifier_client.err; then
      OUTPUT=$(cat /tmp/verifier_client.out 2>/dev/null)
      if [ "$(echo "$OUTPUT" | tr -d '[:space:]')" = "PING" ]; then
        run_result=1
      fi
    fi
  fi

  if [ -n "$PID" ]; then
    kill "$PID" >/dev/null 2>&1
  fi
fi

reward="$run_result"
echo "$reward" > /logs/verifier/reward.txt