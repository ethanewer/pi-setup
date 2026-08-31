#!/bin/bash
# Fleet driver: run author_batch.sh over all batches with limited concurrency.
set -u
ROOT=/Users/ethanewer/pi-setup/evals/general-v2
cd "$ROOT"
CONC=${1:-3}
START=${2:-0}
i=0
for f in tmp/second-tasks/batches/batch_*.json; do
  n=${f##*batch_}; n=${n%.json}; n=$((10#$n))
  [ $n -lt $START ] && continue
  # skip if already completed (has a RESULT line)
  if [ -f "tmp/second-tasks/batch_$(printf %03d $n)/agent.out" ] && grep -q "^RESULT" "tmp/second-tasks/batch_$(printf %03d $n)/agent.out" 2>/dev/null; then
    continue
  fi
  bash tmp/second-tasks/author_batch.sh "$f" &
  while [ "$(jobs -r | wc -l)" -ge $CONC ]; do wait -n; done
  i=$((i+1))
done
wait
echo "FLEET_COMPLETE launched=$i"
