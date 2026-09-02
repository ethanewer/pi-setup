#!/bin/bash
# vine-yonder oracle: install every deliverable program and RUN it to produce
# the required output artifacts. Does real work with real /app paths; never
# reads /tests and never cats a precomputed answer.
set -euo pipefail

# --- 1) deliverable programs / scripts -------------------------------------
cp /solution/fix-fetch.sh      /app/fix-fetch.sh
cp /solution/load-dataset.py   /app/load-dataset.py
cp /solution/chain-query.py    /app/chain-query.py
cp /solution/fix-pipeline.sh   /app/fix-pipeline.sh
cp /solution/submit-spark.sh   /app/submit-spark.sh
cp /solution/run_monitor.py    /app/run_monitor.py
chmod +x /app/fix-fetch.sh /app/fix-pipeline.sh
chmod +x /app/submit-spark.sh /app/run_monitor.py
chmod 755 /app/load-dataset.py /app/chain-query.py

python3 -m py_compile /app/load-dataset.py /app/chain-query.py /app/run_monitor.py

# --- 2) start the platform stack so fetch/load/query can hit live services -------
env MOCK_DATA_DIR=/app/mockdata MOCK_PORT=9000 MOCK_PROXY_PORT=8051 \
    python3 /app/servers.py >/tmp/solve-servers.log 2>&1 &
SERVPID=$!
sleep 3
curl -sf -o /dev/null http://127.0.0.1:9000/page \
    || { echo "oracle: platform stack did not come up"; curl -sf http://127.0.0.1:9000/page || true; }

# --- 3) run the software to produce every required output artifact ----------------
# (1) repair egress fetch -> /app/fetched/page.html
bash /app/fix-fetch.sh >/tmp/solve-fetch.log 2>&1
# (2) load reserved dataset slice -> /app/dataset-report.json
python3 /app/load-dataset.py >/tmp/solve-dataset.log 2>&1
# (3) query live node RPC -> /app/chain-account.json
python3 /app/chain-query.py >/tmp/solve-chain.log 2>&1
# (4) fix+run chained pipeline -> /app/pipeline.out
bash /app/fix-pipeline.sh >/tmp/solve-pipeline.log 2>&1
# (5) Spark runtime (local + standalone-cluster) -> /app/runtimes.txt
bash /app/submit-spark.sh >/tmp/solve-spark.log 2>&1
tail -n 4 /tmp/solve-spark.log
# (6) monitor sweep (~60s) -> /app/monitor.log
python3 /app/run_monitor.py

kill "$SERVPID" 2>/dev/null || true

echo "oracle produced every deliverable (fetched, dataset-report, chain-account, pipeline.out, runtimes.txt, monitor.log)"