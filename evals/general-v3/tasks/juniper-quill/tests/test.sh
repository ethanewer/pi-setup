#!/bin/bash
# juniper-quill verifier. Executes the /app/recover.py deliverable on the visible
# BrightShard warehouse and on each hidden case, recomputes ground truth from the
# damaged sources, and checks JSON/CSV/database consistency, the open-fd recovery
# and the query-performance gate. Ends by writing /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0
if python3 /tests/verify.py; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
