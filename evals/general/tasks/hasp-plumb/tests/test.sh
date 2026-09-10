#!/bin/bash
# Verifier for hasp-plumb (redis-build-operate). Checks, in order:
#   1. the declared deliverables exist: /app/redis.conf, /app/start.sh
#      (executable), the built /app/src/src/redis-server and
#      /app/src/src/redis-cli binaries, and the /app/data directory,
#   2. a server started through the agent's /app/start.sh is the agent-built
#      Redis 8.10.1 (self-reported version, and its config dir is /app/data),
#   3. every hidden workload fixture in /tests/hidden/*/run.sh passes. Each
#      fixture restarts the server through /app/start.sh and asserts a
#      behaviour with /app/src/src/redis-cli against 127.0.0.1:6379.
# Reward is binary and written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
failures=0

HOST=127.0.0.1
PORT=6379
CLI=/app/src/src/redis-cli
SVR=/app/src/src/redis-server

stop_server() {
    "$CLI" -h "$HOST" -p "$PORT" shutdown nosave >/dev/null 2>&1 || true
    pkill -x redis-server 2>/dev/null || true
    sleep 0.4
}

# ---- 1. deliverables --------------------------------------------------------
for d in /app/redis.conf /app/start.sh /app/src/src/redis-server /app/src/src/redis-cli /app/data; do
    if [ ! -e "$d" ]; then
        echo "FAIL: deliverable $d missing" >&2
        failures=1
    fi
done
if [ ! -x /app/start.sh ]; then
    echo "FAIL: /app/start.sh not executable" >&2
    failures=1
fi

# ---- 2. the running server is the agent's own build ------------------------
if [ $failures -eq 0 ] && [ -x /app/start.sh ] && [ -x "$CLI" ] && [ -x "$SVR" ]; then
    stop_server
    bash /app/start.sh
    ready=""
    for i in $(seq 1 60); do
        if "$CLI" -h "$HOST" -p "$PORT" ping >/dev/null 2>&1; then ready=1; break; fi
        sleep 0.2
    done
    if [ -z "$ready" ]; then
        echo "FAIL: /app/start.sh did not bring the server up on $HOST:$PORT" >&2
        failures=1
    else
        version=$("$CLI" -h "$HOST" -p "$PORT" INFO server | sed -n 's/^redis_version:\([0-9.]*\).*/\1/p' | tr -d '\r')
        if [ "$version" != "8.10.1" ]; then
            echo "FAIL: running server reports redis_version '$version', expected 8.10.1 (agent build)" >&2
            failures=1
        else
            echo "server is the agent build: redis_version=8.10.1 (PASS)"
        fi
        dir=$("$CLI" -h "$HOST" -p "$PORT" CONFIG GET dir | sed -n '2p' | tr -d '\r')
        if [ "$dir" != "/app/data" ]; then
            echo "FAIL: CONFIG dir is '$dir', expected /app/data" >&2
            failures=1
        fi
    fi
    stop_server
fi

# ---- 3. hidden workload fixtures -------------------------------------------
for case_dir in /tests/hidden/*/; do
    run="$case_dir/run.sh"
    if [ -f "$run" ]; then
        hlog=/tmp/verifier_hidden_$(basename "$case_dir").log
        if bash "$run" >"$hlog" 2>&1; then
            echo "hidden case $(basename "$case_dir"): PASS"
        else
            echo "FAIL: hidden case $(basename "$case_dir") failed" >&2
            tail -30 "$hlog" >&2
            failures=1
        fi
    fi
done

if [ $failures -eq 0 ]; then
    echo "VERIFIER: all checks passed, reward=1"
    echo 1 > /logs/verifier/reward.txt
else
    echo "VERIFIER: failures present, reward=0" >&2
    echo 0 > /logs/verifier/reward.txt
fi
exit 0