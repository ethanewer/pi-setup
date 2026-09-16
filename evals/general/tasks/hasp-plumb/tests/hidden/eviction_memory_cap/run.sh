#!/bin/bash
# Hidden fixture 2/3: memory ceiling + eviction.
# Reads the server's own ceiling (CONFIG GET maxmemory) and eviction policy,
# then pushes ~120 MB of distinct 1 MB values that carry NO TTL at it. The
# server must accept every write, evict older entries instead of refusing or
# ballooning, keep memory bounded near the ceiling, and still serve the most
# recently written keys.
set -u
HOST=127.0.0.1
PORT=6379
CLI=/app/src/src/redis-cli
fail() { echo "FAIL: $*" >&2; exit 1; }

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

# --- what ceiling and policy did the agent configure? ------------------------
mm=$("$CLI" -h "$HOST" -p "$PORT" CONFIG GET maxmemory | sed -n '2p' | tr -d '\r')
pol=$("$CLI" -h "$HOST" -p "$PORT" CONFIG GET maxmemory-policy | sed -n '2p' | tr -d '\r')
echo "configured: maxmemory=${mm} policy=${pol}"
if [ -z "$mm" ] || [ "$mm" = "0" ] || [ "${mm//[0-9]/}" != "" ] || [ "$mm" -lt 16777216 ] || [ "$mm" -gt 134217728 ]; then
    fail "maxmemory '${mm}' is not a sane tens-of-MB ceiling (16-128MB)"
fi
case "$pol" in
    noeviction) fail "policy is noeviction: server would refuse writes, not evict" ;;
    volatile-*) fail "policy $pol: no-TTL keys are not evictable by this policy" ;;
esac

# --- push 120 MB of distinct 1 MB values past the ceiling ---
value_file=/tmp/hasp_fill.bin
head -c 1048576 /dev/zero | tr '\0' 'q' > "$value_file"
writes_ok=0
for i in $(seq 1 120); do
    out=$("$CLI" -h "$HOST" -p "$PORT" -x set "bulk:$(printf '%03d' "$i")" < "$value_file" 2>&1)
    if echo "$out" | grep -qi "oom\|out of memory\|error"; then
        fail "write bulk:$(printf '%03d' "$i") rejected ($out)"
    fi
done

# --- assertions on the live server ---
sleep 0.5
evicted=$("$CLI" -h "$HOST" -p "$PORT" INFO stats | sed -n 's/^evicted_keys:\([0-9]*\).*/\1/p' | tr -d '\r')
used=$("$CLI" -h "$HOST" -p "$PORT" INFO memory | sed -n 's/^used_memory:\([0-9]*\).*/\1/p' | tr -d '\r')
dbsize=$("$CLI" -h "$HOST" -p "$PORT" dbsize | tr -d '\r')

[ "$evicted" -gt 10 ] || fail "eviction did not happen under the ceiling (evicted_keys=$evicted)"
limit=$(( (mm + 33554432) ))   # ceiling + 32 MB slack
[ "$used" -lt "$limit" ] || fail "memory not bounded near ceiling: used=$used limit=$limit"
[ "$dbsize" -lt 120 ] || fail "keyspace not bounded: dbsize=$dbsize (expected << 120)"

# most recently written key must have survived (oldest-first eviction)
got=$("$CLI" -h "$HOST" -p "$PORT" get bulk:120 2>/dev/null)
want=$(cat "$value_file")
[ "$got" = "$want" ] || fail "most recent key bulk:120 was evicted/lost"  

rm -f "$value_file"
echo "fixture eviction_memory_cap: PASS (evicted=$evicted used=$used maxmemory=$mm dbsize=$dbsize)"
exit 0