#!/bin/bash
# bracket-flood reproducer: start a throwaway redis on port 7777 and run the
# Tcl reproducer against it. Prints the symptom the bug produces.
set -u
SRC=/app/src
PORT=7777
LOG=/tmp/bf-repro-server.log

trap '"$SRC/src/redis-cli" -p "$PORT" shutdown nosave >/dev/null 2>&1 || true' EXIT

pkill -f '/app/src/src/redis-server' 2>/dev/null || true
sleep 0.5
"$SRC/src/redis-server" --port "$PORT" --daemonize yes > "$LOG" 2>&1

ready=0
for _ in $(seq 1 50); do
    if ( exec 3<>/dev/tcp/127.0.0.1/$PORT ) 2>/dev/null; then ready=1; break; fi
    sleep 0.2
done
if [ "$ready" != 1 ]; then
    echo "ERROR: redis-server on port $PORT never became ready"
    tail -5 "$LOG" >&2
    exit 1
fi

export PORT
tclsh /app/reproduce.tcl
rc=$?

"$SRC/src/redis-cli" -p "$PORT" shutdown nosave > /dev/null 2>&1 || true
exit $rc