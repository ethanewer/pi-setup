#!/bin/bash
set -euo pipefail
# Real work: install the two analysis programs and run them on /app fixtures to
# produce every deliverable artifact by DOING the work (not reading answers).
cp /solution/logproc.py /app/logproc.py
cp /solution/respond.py /app/respond.py
chmod +x /app/logproc.py /app/respond.py
mkdir -p /app/logs

python3 /app/logproc.py rounds /app/events.ndjson /app/logs
# the rounds subcommand writes the round deliverables directly under /app/logs;
# assert each of the three declared round artifacts was produced by that run.
for f in /app/logs/round1.out /app/logs/round2.out /app/logs/round3.out; do
  [ -f "$f" ] || { echo "solve.sh: missing $f" >&2; exit 1; }
done
python3 /app/logproc.py frames /app/traces.txt /app/logs/frames.json
python3 /app/logproc.py dates /app/lines.txt /app/logs/dates.tsv
python3 /app/respond.py 203.0.113.55 /app/activity_a.jsonl /app/activity_b.jsonl /app/incident.json

echo "solve.sh complete"