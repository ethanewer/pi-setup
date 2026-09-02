#!/bin/bash
# vine-yonder verifier: executes every delivered program/artifact in /app and
# validates the end-to-end behaviour against the shipped fixtures and the
# hidden cases mounted at /tests/hidden. Writes 0/1 to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

VINE=/tests/vine_check.py
LOG=/tmp/vine-verifier.log

pass=1
fail() { pass=0; echo "VINE FAIL: $*"; }

echo "===== vine-yonder verifier (pid $$) ====="

# ---- 0) start the platform stack (default data under /app/mockdata) ----
env MOCK_DATA_DIR=/app/mockdata MOCK_PORT=9000 MOCK_PROXY_PORT=8051 \
    python3 /app/servers.py >/tmp/vine-servers.log 2>&1 &
SERVPID=$!
sleep 3
if ! curl -sf -o /dev/null http://127.0.0.1:9000/page; then
    fail "platform status page not served"
fi

# ---- 1) outbound fetch repair + end-to-end content ----
if [ ! -x /app/fix-fetch.sh ] && [ ! -f /app/fix-fetch.sh ]; then
    fail "missing /app/fix-fetch.sh"
else
    if ! bash /app/fix-fetch.sh >>"$LOG" 2>&1; then
        fail "fix-fetch.sh exited non-zero"
    else
        if [ ! -s /app/fetched/page.html ]; then
            fail "no page saved by fix-fetch.sh"
        elif ! cmp -s /app/fetched/page.html /app/mockdata/page.html; then
            fail "fetched page differs byte-for-byte from served content"
        fi
        # root cause neutralised: the broken proxy override must be gone/empty
        if [ -s /app/override/proxy.txt ]; then
            fail "broken proxy override still active"
        fi
    fi
fi

# ---- 2) hub dataset load (visible + hidden) ----
if [ ! -f /app/load-dataset.py ]; then
    fail "missing /app/load-dataset.py"
else
    if ! python3 /app/load-dataset.py >>"$LOG" 2>&1; then
        fail "load-dataset.py failed (visible)"
    else
        python3 "$VINE" dataset /app/dataset-report.json \
            /app/mockdata/datasets/rose-orchard || fail "visible dataset mismatch"
    fi
    # hidden dataset served from a separate data dir on a separate port
    env MOCK_DATA_DIR=/tests/hidden/h1_data MOCK_PORT=9111 MOCK_PROXY_PORT=9140 \
        python3 /app/servers.py >/tmp/vine-h1-server.log 2>&1 &
    sleep 2
    if ! python3 /app/load-dataset.py http://127.0.0.1:9111/hub/aurora-grove >>"$LOG" 2>&1; then
        fail "load-dataset.py failed (hidden)"
    else
        python3 "$VINE" dataset /app/dataset-report.json \
            /tests/hidden/h1_data/datasets/aurora-grove \
            || fail "hidden dataset mismatch"
    fi
fi

# ---- 3) blockchain RPC query (visible + hidden) ----
if [ ! -f /app/chain-query.py ]; then
    fail "missing /app/chain-query.py"
else
    if ! python3 /app/chain-query.py >>"$LOG" 2>&1; then
        fail "chain-query.py failed (visible)"
    else
        python3 "$VINE" chain /app/chain-account.json \
            /app/mockdata/chain/chain.json 0xF00D || fail "visible chain mismatch"
    fi
    env MOCK_DATA_DIR=/tests/hidden/h2_chain MOCK_PORT=9122 MOCK_PROXY_PORT=9150 \
        python3 /app/servers.py >/tmp/vine-h2-server.log 2>&1 &
    sleep 2
    if ! python3 /app/chain-query.py http://127.0.0.1:9122/rpc 0x0C7E >>"$LOG" 2>&1; then
        fail "chain-query.py failed (hidden)"
    else
        cp /app/chain-account.json /tmp/chain-h2.json
        python3 "$VINE" chain /tmp/chain-h2.json \
            /tests/hidden/h2_chain/chain/chain.json 0x0C7E || fail "hidden chain mismatch"
    fi
fi

# ---- 4) Spark local + standalone-cluster runs with captured runtimes ----
if [ ! -f /app/submit-spark.sh ]; then
    fail "missing /app/submit-spark.sh"
else
    if ! bash /app/submit-spark.sh >>"$LOG" 2>&1; then
        fail "submit-spark.sh failed"
    else
        python3 "$VINE" spark /app/runtimes.txt /app/logs /app/events \
            || fail "spark runs/runtimes invalid"
        code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080 2>/dev/null)
        if [ "$code" != "200" ]; then
            fail "spark master UI (8080) not reachable after submit"
        fi
    fi
fi

# ---- 5) chained pipeline dependency/dir repair (visible + hidden) ----
if [ ! -f /app/fix-pipeline.sh ]; then
    fail "missing /app/fix-pipeline.sh"
else
    if ! bash /app/fix-pipeline.sh >>"$LOG" 2>&1; then
        fail "fix-pipeline.sh failed (visible)"
    else
        python3 "$VINE" pipeline /app/pipeline.out /app/pipeline \
            || fail "visible pipeline not repaired/ordered"
    fi
    cp -r /tests/hidden/h3_pipeline /tmp/h3_pipeline
    if ! bash /app/fix-pipeline.sh /tmp/h3_pipeline /tmp/ph3.out >>"$LOG" 2>&1; then
        fail "fix-pipeline.sh failed on hidden pipeline"
    else
        python3 "$VINE" pipeline /tmp/ph3.out /tmp/h3_pipeline \
            || fail "hidden pipeline not repaired/ordered"
    fi
    rm -rf /tmp/h3_pipeline
fi

# ---- 6) monitor log spanning ~60s at ~10s intervals ----
if [ ! -s /app/monitor.log ]; then
    fail "missing/incomplete /app/monitor.log"
else
    python3 "$VINE" monitor /app/monitor.log || fail "monitor log invalid"
fi

# ---- outcome ----
if [ "$pass" = "1" ]; then
    reward=1
    echo "vine-yonder: ALL CHECKS PASSED"
else
    reward=0
    echo "vine-yonder: FAILURES PRESENT (see stdio output)"
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0