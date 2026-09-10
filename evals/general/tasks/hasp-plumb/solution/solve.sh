#!/bin/bash
# Oracle for hasp-plumb: build Redis from the pinned upstream clone, write a
# crash-safe, memory-capped configuration, ship /app/start.sh, and prove the
# server comes up. Reads only /app/src and /app/... never /tests.
set -u

BIN=/app/src/src/redis-server
CLI=/app/src/src/redis-cli

echo "oracle: building redis-server and redis-cli from /app/src at 1 CPU"
make -C /app/src -j1 redis-server redis-cli >/tmp/oracle_make.log 2>&1
status=$?
if [ $status -ne 0 ]; then
    echo "oracle: make failed (exit $status); tail:" >&2
    tail -20 /tmp/oracle_make.log >&2
    exit 1
fi
if [ ! -x "$BIN" ] || [ ! -x "$CLI" ]; then
    echo "oracle: built binaries missing ($BIN / $CLI)" >&2
    exit 1
fi

mkdir -p /app/data

cat > /app/redis.conf <<'CONF'
# hasp-plumb oracle deployment config: crash-safe persistence via the
# append-only file, memory ceiling with oldest-first eviction.
bind 127.0.0.1
port 6379
dir /app/data
save ""
appendonly yes
appendfsync everysec
maxmemory 64mb
maxmemory-policy allkeys-lru
CONF

cat > /app/start.sh <<'SH'
#!/bin/bash
# Start the Redis server built from /app/src with /app/redis.conf on
# 127.0.0.1:6379. Idempotent: stops whatever is already listening, then
# starts a fresh instance and returns once it answers PING.
set -u
BIN=/app/src/src/redis-server
CLI=/app/src/src/redis-cli
CONF=/app/redis.conf

$CLI -h 127.0.0.1 -p 6379 shutdown nosave >/dev/null 2>&1 || true
pkill -x redis-server 2>/dev/null || true
sleep 0.5

if [ ! -f "$CONF" ]; then
    echo "start.sh: config $CONF missing" >&2
    exit 1
fi

mkdir -p /app/data
nohup "$BIN" "$CONF" >>/app/data/server.log 2>&1 &
disown 2>/dev/null || true

for i in $(seq 1 60); do
    if "$CLI" -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1; then
        exit 0
    fi
    sleep 0.2
done
echo "start.sh: server did not become ready within 12s" >&2
exit 1
SH
chmod +x /app/start.sh

echo "==oracle: proving the deliverable stack== " 
bash /app/start.sh
ok=$?
if [ $ok -ne 0 ]; then
    echo "oracle: /app/start.sh could not bring the server up" >&2
    exit 1
fi
echo "ping: $($CLI -h 127.0.0.1 -p 6379 ping)"
echo "version: $($CLI -h 127.0.0.1 -p 6379 INFO server | sed -n 's/^redis_version://p')"
$CLI -h 127.0.0.1 -p 6379 shutdown nosave >/dev/null 2>&1 || true
echo "oracle: done"
exit 0