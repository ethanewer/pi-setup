#!/bin/bash
# Start a daemonized redis-server on 127.0.0.1:<port> with no persistence,
# and exit 0 only once the server answers PONG (bounded wait).
# Idempotent: if something already answers on the port, exit 0 immediately.
set -u
PORT="${1:-6379}"
DIR="/tmp/redis-$PORT"
mkdir -p "$DIR"

if redis-cli -p "$PORT" ping >/dev/null 2>&1; then
  echo "redis already up on $PORT"
  exit 0
fi

redis-server --bind 127.0.0.1 --port "$PORT" --daemonize yes \
  --save "" --appendonly no --dir "$DIR" \
  --pidfile "$DIR/redis.pid" --logfile "$DIR/redis.log"

for _ in $(seq 1 50); do
  if redis-cli -p "$PORT" ping 2>/dev/null | grep -q PONG; then
    echo "redis up on $PORT"
    exit 0
  fi
  sleep 0.2
done

echo "redis failed to start on $PORT" >&2
[ -f "$DIR/redis.log" ] && cat "$DIR/redis.log" >&2 || true
exit 1