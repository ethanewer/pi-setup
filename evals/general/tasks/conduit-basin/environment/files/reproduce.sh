#!/bin/bash
# Reproducer for the missing biggest-key line for zero-size keys.
#
# Starts a throwaway Redis server, stores a single empty string key, and
# drives `redis-cli --bigkeys` and `redis-cli --keystats` against it,
# printing what the two keyspace-summary modes report and ending with
# STATE=BUGGY (the bug is present: the key is counted but never reported as
# biggest) or STATE=FIXED (the biggest-key lines name the empty key).
set -u

SRC="${SRC:-/app/src}"
PORT=$(( 20000 + ($$ % 20000) ))
TMP=$(mktemp -d)

"$SRC/src/redis-server" \
    --port "$PORT" \
    --bind 127.0.0.1 \
    --save "" \
    --appendonly no \
    --dir "$TMP" \
    --daemonize yes \
    --pidfile "$TMP/redis.pid" \
    >"$TMP/server.log" 2>&1

CLI=("$SRC/src/redis-cli" -h 127.0.0.1 -p "$PORT")

cleanup() {
    "${CLI[@]}" shutdown nosave >/dev/null 2>&1 || true
    rm -rf "$TMP"
}
trap cleanup EXIT

ok=0
for _ in $(seq 1 100); do
    if "${CLI[@]}" ping 2>/dev/null | grep -q PONG; then ok=1; break; fi
    sleep 0.1
done
if [ "$ok" != 1 ]; then
    echo "server did not come up; log:" >&2
    cat "$TMP/server.log" >&2
    exit 1
fi

"${CLI[@]}" set empty "" >/dev/null

echo "== redis-cli --bigkeys =="
BIG=$("${CLI[@]}" --bigkeys 2>&1)
echo "$BIG" | grep -E "Sampled|Biggest string|strings with|Total key length" || true

echo
echo "== redis-cli --keystats =="
STATS=$("${CLI[@]}" --keystats 2>&1)
echo "$STATS" | sed -n '/^--- Top size per type ---/,/^$/p' | head -6
echo "--"
echo "$STATS" | sed -n '/^--- Top length and cardinality per type ---/,/^$/p' | head -6

if echo "$BIG" | grep -q 'Biggest string found "empty" has 0 bytes'; then
    echo "STATE=FIXED"
else
    echo "STATE=BUGGY"
fi