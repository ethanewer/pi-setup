#!/bin/bash
# Oracle for flume-schema. Installs the real solver as the deliverable loop
# and RUNS it on the visible transcript to produce /app/run_A.json. This does
# the actual work; it never reads /tests and never embeds a precomputed log.
set -eu

cp /solution/solver.py /app/agent_loop.py
chmod +x /app/agent_loop.py

python3 /app/agent_loop.py /app/transcripts/session_A.json /app/run_A.json

echo "oracle produced /app/agent_loop.py and /app/run_A.json"