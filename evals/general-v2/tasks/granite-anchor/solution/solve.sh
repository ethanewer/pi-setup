#!/bin/bash
# Oracle for tasks/granite-anchor (executes-deliverable).
# Writes the real /app/search.py deliverable, then RUNS it on the primary
# config to produce every /app artifact. Never reads /tests.
set -u
cd /app

echo "== [1] install the search driver =="
cp /solution/search.py /app/search.py
chmod +x /app/search.py

echo "== [2] run the search on /app/config.json ==="
python3 /app/search.py /app/config.json /app

echo "== deliverables on disk =="
ls -1 /app/frontier_*.txt /app/frontier.sha256 /app/depth_summary.txt \
      /app/move_trace.json /app/dag_edges.csv /app/search.py

echo "== sanity glance =="
cat /app/depth_summary.txt
cat /app/dag_edges.csv
cat /app/move_trace.json

echo "SOLVE_DONE"
exit 0