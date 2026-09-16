#!/usr/bin/env bash
# Windlass DispatchService serve script (deliverable).
#
# Usage: serve.sh [PORT]
#
# Makes the repository consistent with the authoritative schema
# (proto/dispatch.proto), builds the Go server, starts it listening on
# 0.0.0.0:PORT, waits until it accepts connections, then exits 0.
# Writes the server PID to $REPO/.server.pid.
set -euo pipefail

PORT="${1:-50333}"
REPO="/app/windlass-dispatch"
cd "$REPO"

# 1) keep every generated artifact consistent with the authoritative schema
protoc -I proto --go_out=. --go-grpc_out=. proto/dispatch.proto
python3 -m grpc_tools.protoc -I proto --python_out=client --grpc_python_out=client proto/dispatch.proto

# 2) build the server
go build -o windlass-server

# 3) start the server and record its pid
./windlass-server --port="$PORT" &
PID=$!
echo "$PID" > "$REPO/.server.pid"

# 4) wait for readiness (bounded poll, no fixed sleeps)
python3 - "$PORT" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
deadline = time.time() + 180
while time.time() < deadline:
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=0.5)
        s.close()
        sys.exit(0)
    except OSError:
        time.sleep(0.25)
sys.exit(1)
PY