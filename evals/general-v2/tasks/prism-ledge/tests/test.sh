#!/bin/bash
# Verifier for tasks/prism-ledge. Runs after the agent finishes. Executes every
# deliverable (/app/pipeline.py, /app/cdecode, /app/out.csv) over the hidden
# clips under /tests/hidden and writes 0/1 to /logs/verifier/reward.txt.
set -uo pipefail

cd /app
REWARD=0
reason=""

# ---- deliverables present ------------------------------------------------
if [ ! -x /app/pipeline.py ]; then reason="pipeline.py missing/not executable"; fi
if [ ! -x /app/cdecode ]; then reason="cdecode missing/not executable"; fi
if [ ! -s /app/out.csv ]; then reason="out.csv missing"; fi
if [ ! -s /app/analysis.json ]; then reason="analysis.json missing"; fi

# ---- per hidden clip ------------------------------------------------------
declare -A PHRASE=( [track_x]=3LV4N2 [lane_a]=XV4K7N [bench_y]=H7Z2W4 )
ALLPASS=1
for clip in /tests/hidden/*/; do
  name=$(basename "$clip")
  expected="${PHRASE[$name]:-}"
  if [ -z "$expected" ]; then
    echo "clip $name: no expected phrase bound"; ALLPASS=0; continue
  fi
  outdir="/tmp/o_$name"
  rm -rf "$outdir"
  if ! python3 /app/pipeline.py "$clip" "$outdir" >/tmp/p_$name.log 2>&1; then
    echo "clip $name: pipeline run failed"; sed -n '1,20p' /tmp/p_$name.log; ALLPASS=0; continue
  fi
  if ! python3 /tests/verify.py "$clip" "$outdir/out.csv" "$outdir/analysis.json" "$expected" /app/cdecode; then
    echo "clip $name: verify failed"; ALLPASS=0
  fi
done

if [ -z "$reason" ] && [ "$ALLPASS" = "1" ]; then
  REWARD=1
fi

mkdir -p /logs/verifier
echo "$REWARD" > /logs/verifier/reward.txt
echo "REWARD=$REWARD reason=${reason:-ok}"
exit 0