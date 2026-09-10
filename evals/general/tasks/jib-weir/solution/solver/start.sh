#!/bin/bash
# jib-weir: build (if needed) and start the catalogue API server.
#
# Contract (the verifier depends on exactly this):
#   bash /app/start.sh [PORT] [DATA_FILE]
#   - PORT      loopback TCP port, default 8780
#   - DATA_FILE JSON dataset {"items":[...]}, default /app/data/media.json
#   - builds the TypeScript project (incremental) if the build output is stale
#   - starts the server on 127.0.0.1:PORT in the background
#   - waits until GET /health answers 200 (bounded)
#   - prints one line:  READY port=<PORT> pid=<PID>
#   - writes the server pid to /tmp/jib-weir-server.pid
#   - exits 0 on success, non-zero with diagnostics on failure
#
# A previous instance from an earlier start.sh invocation is stopped first, so
# the script is idempotent.
set -u

PORT="${1:-8780}"
DATA="${2:-/app/data/media.json}"
PIDFILE=/tmp/jib-weir-server.pid
LOG=/tmp/jib-weir-server.log

# Stop a stale instance from a previous invocation.
if [ -f "$PIDFILE" ]; then
  OLD_PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
fi

cd /app || { echo "no /app" >&2; exit 1; }

# Build incrementally whenever any source is newer than the compiled output.
if [ ! -f dist/src/server.js ]; then
  BUILD_NEEDED=1
elif find src scripts -name '*.ts' -newer dist/src/server.js 2>/dev/null | grep -q .; then
  BUILD_NEEDED=1
else
  BUILD_NEEDED=0
fi
if [ "$BUILD_NEEDED" = "1" ]; then
  node_modules/.bin/tsc -p tsconfig.json > /tmp/jib-build.log 2>&1 || {
    echo "BUILD FAILED (see /tmp/jib-build.log)" >&2
    tail -30 /tmp/jib-build.log >&2
    exit 1
  }
fi

nohup node dist/src/server.js "$PORT" "$DATA" > "$LOG" 2>&1 &
PID=$!
echo "$PID" > "$PIDFILE"

# Bounded readiness poll against /health.
for _ in $(seq 1 80); do
  if node -e "fetch('http://127.0.0.1:$PORT/health').then(r=>process.exit(r.status===200?0:1)).catch(()=>process.exit(1))" > /dev/null 2>&1; then
    echo "READY port=$PORT pid=$PID"
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "SERVER EXITED EARLY (see $LOG)" >&2
    tail -30 "$LOG" >&2 2>/dev/null || true
    exit 1
  fi
  sleep 0.5
done
echo "SERVER NOT READY WITHIN BUDGET (see $LOG)" >&2
tail -30 "$LOG" >&2 2>/dev/null || true
exit 1