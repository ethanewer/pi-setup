#!/usr/bin/env bash
# Verifier: executes /app/parse.py on the visible fixtures AND hidden cases,
# then checks every deliverable + regenerated output. Writes REWARD to
# /logs/verifier/reward.txt.
set -u

DIFF() { python3 /tests/helper.py "$@" >/dev/null 2>&1; }

reward=1

# --- deliverable existence -------------------------------------------------
for f in /app/parse.py /app/out.tsv /app/tree.json /app/qdp.tsv; do
  [ -f "$f" ] || reward=0
done

# --- re-run on the visible fixture and compare ------------------------------
rm -rf /tmp/vis && mkdir -p /tmp/vis
if python3 /app/parse.py /app/data /tmp/vis >/dev/null 2>&1; then
  :
else
  reward=0
fi
DIFF tsv /tmp/vis/out.tsv  /tests/expected/out.tsv  || reward=0
DIFF json /tmp/vis/tree.json /tests/expected/tree.json || reward=0
DIFF tsv /tmp/vis/qdp.tsv  /tests/expected/qdp.tsv  || reward=0

# --- delivered /app artifacts must match the re-run ------------------------
cmp -s /app/out.tsv /tmp/vis/out.tsv || reward=0
cmp -s /app/qdp.tsv /tmp/vis/qdp.tsv || reward=0
python3 - <<'PY' || reward=0
import json, sys
try:
    a = json.load(open('/app/tree.json'))
    b = json.load(open('/tmp/vis/tree.json'))
    sys.exit(0 if a == b else 1)
except Exception:
    sys.exit(1)
PY

# --- hidden cases -----------------------------------------------------------
for c in raptor_fall codfish_bend quail_dune; do
  rm -rf /tmp/h_$c && mkdir -p /tmp/h_$c
  if python3 /app/parse.py /tests/hidden/$c/input /tmp/h_$c >/dev/null 2>&1; then
    :
  else
    reward=0
  fi
  DIFF tsv  /tmp/h_$c/out.tsv  /tests/hidden/$c/expected/out.tsv  || reward=0
  DIFF json /tmp/h_$c/tree.json /tests/hidden/$c/expected/tree.json || reward=0
  DIFF tsv  /tmp/h_$c/qdp.tsv  /tests/hidden/$c/expected/qdp.tsv  || reward=0
done

mkdir -p /logs/verifier
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"