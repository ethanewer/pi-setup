#!/bin/bash
# pennant-caboose oracle reproduction.
#
# Drives a real redis server through the scenario that exposes the defect:
# a stream with a consumer group that has read everything, a trim that
# shrinks the stream, and XSETID ... ENTRIESADDED lowering the stream's
# entry counter below the group's read position. Reports what the group
# actually reports (entries-read, lag) and whether a snapshot taken at that
# point loads back (DEBUG RELOAD), then prints the verdict.
#
# Honours the verifier contract: optional first argument = server binary;
# else $REDIS_SERVER_BIN; else /app/src/src/redis-server. Port from
# $REDIS_PORT, default 6391. Always exits 0 when it ran to completion.
set -u

BIN="${1:-${REDIS_SERVER_BIN:-/app/src/src/redis-server}}"
PORT="${REDIS_PORT:-6391}"
CLI=/app/src/src/redis-cli
WORK=$(mktemp -d /tmp/pcrepro.XXXXXX)

server_pid=""
cleanup() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

"$BIN" --port "$PORT" --save "" --appendonly no --enable-debug-command yes \
    --daemonize yes --pidfile "$WORK/redis.pid" --dir "$WORK" --logfile "$WORK/log"
server_pid=$(cat "$WORK/redis.pid" 2>/dev/null || true)

up=0
for _ in $(seq 1 50); do
    if "$CLI" -p "$PORT" PING >/dev/null 2>&1; then up=1; break; fi
    sleep 0.1
done
if [ "$up" != 1 ]; then
    echo "server $BIN on port $PORT did not come up"
    echo "VERDICT: BUGGY"
    exit 0
fi

R="$CLI -p $PORT"

# Scenario: 10 entries, a group that reads all 10, the stream trimmed to 2,
# then the counter lowered to 2 -- below the group's read position of 10.
for i in $(seq 1 10); do $R XADD s \* f v$i > /dev/null; done
$R XGROUP CREATE s g 0 > /dev/null
$R XREADGROUP GROUP g c COUNT 10 STREAMS s '>' > /dev/null
$R XTRIM s MAXLEN 2 > /dev/null
top=$($R XINFO STREAM s | awk '/last-generated-id/{getline; print $1; exit}')
$R XSETID s "$top" ENTRIESADDED 2 > /dev/null

echo "group info: $($R XINFO GROUPS s | tr '\n' ' ')"
entries_read=$($R XINFO GROUPS s | awk '/entries-read/{getline; print $1; exit}')
lag=$($R XINFO GROUPS s | awk '/lag/{getline; print $1; exit}')

reload_out=$($R DEBUG RELOAD 2>&1)
reload_rc=$?
echo "DEBUG RELOAD rc=$reload_rc: $reload_out"

buggy=0
[ "${entries_read:-}" = "2" ] || buggy=1
[ "${lag:-}" = "0" ] || buggy=1
if [ "$reload_rc" -ne 0 ] || ! printf '%s' "$reload_out" | grep -q '^OK'; then
    buggy=1
fi

if [ "$buggy" = 1 ]; then
    echo "VERDICT: BUGGY"
else
    echo "VERDICT: FIXED"
fi
exit 0