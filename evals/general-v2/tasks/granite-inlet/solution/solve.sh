#!/bin/bash
# granite-inlet oracle: author the deliverables by writing the wiring scripts,
# register + evaluate the fixtures, and persist the leaderboard pick. Never
# reads /tests.
set -euo pipefail

install -m 0644 /solution/tasks.yaml /app/tasks.yaml
install -m 0644 /solution/register_tasks.py /app/register_tasks.py
install -m 0644 /solution/wire_cli.py /app/wire_cli.py
install -m 0644 /solution/fetch_leaderboard.py /app/fetch_leaderboard.py
install -m 0755 /solution/run_eval.sh /app/run_eval.sh
chmod +x /app/register_tasks.py /app/wire_cli.py /app/fetch_leaderboard.py

# register the classification task in the harness
python3 /app/register_tasks.py

# run the visible evaluation suite (classification + retrieval deliverables)
bash /app/run_eval.sh

# fetch the live leaderboard page at runtime over HTTP and emit the top model
python3 -m http.server 8877 --directory /app/board/www >/dev/null 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
sleep 1.5
python3 /app/fetch_leaderboard.py http://127.0.0.1:8877/index.html
kill $SRV 2>/dev/null || true
trap - EXIT

# sanity: every deliverable must exist
for f in \
  /app/tasks.yaml \
  /app/register_tasks.py \
  /app/run_eval.sh \
  /app/results/channel_fathom/sprint_07.json \
  /app/results/aperture_map/sprint_07.json \
  /app/leaderboard_top.txt ; do
  [ -f "$f" ] || { echo "oracle missing deliverable $f" >&2; exit 1; }
done
echo "granite-inlet oracle complete"