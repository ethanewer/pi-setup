#!/bin/bash
# Hidden fixture 3/3: rich typed workload + TTL surviving a second restart.
# Exercises more of the server's surface (sets, sorted sets, lists, counters,
# expiring tokens), then SIGKILLs and restarts through /app/start.sh once more
# and asserts the full final state.
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

stop_server
rm -rf /app/data/appendonlydir /app/data/dump.rdb /app/data/*.log
start_server

# --- typed workload ------------------------------------------------------------
for i in 5 3 9 1 7; do
    "$CLI" -h "$HOST" -p "$PORT" sadd tags:1 "tag:$i" >/dev/null || fail "sadd tag:$i"
done
"$CLI" -h "$HOST" -p "$PORT" zadd scores:1 5 alpha >/dev/null
"$CLI" -h "$HOST" -p "$PORT" zadd scores:1 9 beta  >/dev/null
"$CLI" -h "$HOST" -p "$PORT" zadd scores:1 2 gamma >/dev/null
"$CLI" -h "$HOST" -p "$PORT" set token:1 "abc-123" >/dev/null
"$CLI" -h "$HOST" -p "$PORT" expire token:1 600 >/dev/null
"$CLI" -h "$HOST" -p "$PORT" incr counter:2 >/dev/null
"$CLI" -h "$HOST" -p "$PORT" incr counter:2 >/dev/null
"$CLI" -h "$HOST" -p "$PORT" set str:1 "second-run" >/dev/null
"$CLI" -h "$HOST" -p "$PORT" lpush q:1 tail >/dev/null
"$CLI" -h "$HOST" -p "$PORT" lpush q:1 head >/dev/null
"$CLI" -h "$HOST" -p "$PORT" rpush q:1 end  >/dev/null

sleep 1.6
# hard-kill every live instance (see aof_crash_survival for the zombie note)
pkill -9 -x redis-server 2>/dev/null || true
for i in $(seq 1 50); do
    "$CLI" -h "$HOST" -p "$PORT" ping >/dev/null 2>&1 || break
    sleep 0.1
done
"$CLI" -h "$HOST" -p "$PORT" ping >/dev/null 2>&1 && fail "server still up after SIGKILL"

start_server

# --- full final-state assert after the second restart ---------------------------
eq "$("$CLI" -h "$HOST" -p "$PORT" scard tags:1)" "5" "set cardinality survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" smembers tags:1 | sort | tr -d '\n')" "tag:1tag:3tag:5tag:7tag:9" "set members survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" zscore scores:1 beta)" "9" "sorted-set score survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" zcard scores:1)" "3" "sorted-set cardinality survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" get token:1)" "abc-123" "token value survived"
ttl=$("$CLI" -h "$HOST" -p "$PORT" ttl token:1 | tr -d '\r')
[ "$ttl" -gt 0 ] && [ "$ttl" -le 600 ] || fail "token TTL not preserved (ttl=$ttl)"
eq "$("$CLI" -h "$HOST" -p "$PORT" get counter:2)" "2" "counter survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" get str:1)" "second-run" "string overwrite survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" lrange q:1 0 -1 | tr '\n' '|')" "head|tail|end|" "list order survived"
eq "$("$CLI" -h "$HOST" -p "$PORT" dbsize)" "6" "keyspace size survived"

echo "fixture types_ttl_survival: PASS (typed keyspace + TTL across a second restart)"
exit 0