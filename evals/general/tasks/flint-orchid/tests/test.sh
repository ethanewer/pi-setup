#!/bin/bash
# flint-orchid verifier (runs as root after the agent finishes; /tests read-only).
set -uo pipefail
PY="$(command -v python3)"
reward=1

# Existence gate: every deliverable must be present.
for f in \
  /app/form_fields.json /app/financials.json /app/query.rq /app/results.csv \
  /app/decode_mesh.py /app/mesh_arrays.npz \
  /app/parse_form.py /app/parse_financials.py ; do
  if [ ! -e "$f" ]; then
    echo "VERIFIER: missing deliverable $f" >&2
    reward=0
  fi
done

# Deep independent verification (executes every /app tool on hidden inputs).
if [ "$reward" = 1 ]; then
  if ! "$PY" /tests/verify.py; then
    reward=0
  fi
fi

mkdir -p /logs/verifier
echo "$reward" > /logs/verifier/reward.txt
echo "flint-orchid reward=$reward"
