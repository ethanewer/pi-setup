#!/bin/bash
# Hidden fixture 1/3: crash-safe persistence.
# Writes a small typed keyspace, lets the durability window pass, SIGKILLs
# the server (no graceful shutdown), restarts through the agent's
# /app/start.sh, and asserts the whole keyspace survived plus a persistence
# artifact exists on disk under /app/data.
set -u
HOST=127.0.0.1
PORT=6379
CLI=/app/src/src/redis-cli
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3 (got '$1' want '$2')"; }

stop_server() {
    "$CLI" -h "$HOST" -p "$PORT" shutdown nosave >/dev/null 2>&1 || true
    pkill -x redis-server 2>/dev/null || true
    sleep 0.4
}
start_server() {
    bash /app/start.sh || fail "start.sh exit $?"
    for i in $(seq 1 60); do
        "$CLI" -h "$HOST" -p "$PORT" ping >/dev/null 2>&1 && return 0
        sleep 0.2
    done
    fail "server not ready after start.sh"
}

# hermetically reset on-disk state from earlier cases
stop_server
rm -rf /app/data/appendonlydir /app/data/dump.rdb /app/data/*.log
start_server

# --- acknowledged writes ----------------------------------------------------
"$CLI" -h "$HOST" -p "$PORT" set str:1 "hello-world" >/dev/null || fail "set str:1"
"$CLI" -h "$HOST" -p "$PORT" set counter:1 0 >/dev/null
"$CLI" -h "$HOST" -p "$PORT" incr counter:1 >/dev/null
"$CLI" -h "$HOST" -p "$PORT" incr counter:1 >/dev/null
"$CLI" -h "$HOST" -p "$PORT" incr counter:1 >/dev/null
for i in alpha beta gamma; do
    "$CLI" -h "$HOST" -p "$PORT" rpush list:1 "$i" >/dev/null || fail "rpush $i"
done
"$CLI" -h "$HOST" -p "$PORT" hset hash:1 name "hasp-plumb" role primary >/dev/null || fail "hset"
"$CLI" -h "$HOST" -p "$PORT" setex exp:1 300 "will-outlive-the-crash" >/dev/null || fail "setex"

# let any deferred fsync land, then hard-kill the process (no graceful stop)
sleep 1.6
# A killed redis-server is reparented to PID 1 and becomes an un-reaped
# zombie (inert: no fds, no listener). Kill every live instance so the
# listener is really gone; zombies do not hold the port.
pkill -9 -x redis-server 2>/dev/null || true
for i in $(seq 1 50); do
    "$CLI" -h "$HOST" -p "$PORT" ping >/dev/null 2>&1 || break
    sleep 0.1
done
"$CLI" -h "$HOST" -p "$PORT" ping >/dev/null 2>&1 && fail "server still up after SIGKILL"

# restart through the agent's deliverable script
start_server

# --- the whole acknowledged keyspace must be back ----------------------------
eq "$("$CLI" -h "$HOST" -p "$PORT" get str:1)" "hello-world" "string survived SIGKILL+restart"
eq "$("$CLI" -h "$HOST" -p "$PORT" get counter:1)" "3" "counter incremented 3x survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" llen list:1)" "3" "list survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" lindex list:1 2)" "gamma" "list order survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" hget hash:1 name)" "hasp-plumb" "hash field survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" get exp:1)" "will-outlive-the-crash" "TTL key value survived"
ttl=$("$CLI" -h "$HOST" -p "$PORT" ttl exp:1)
[ "$ttl" -gt 0 ] && [ "$ttl" -le 300 ] || fail "TTL not preserved (ttl=$ttl)"

# a persistence artifact must actually be on disk, under /app/data
if [ ! -d /app/data/appendonlydir ] && [ ! -f /app/data/dump.rdb ]; then
    find /app/data -maxdepth 2 | sed 's/^/    /' >&2
    fail "no persistence artifact (appendonlydir or dump.rdb) under /app/data"
fi
echo "fixture aof_crash_survival: PASS (acknowledged writes survived SIGKILL + restart)"
exit 0