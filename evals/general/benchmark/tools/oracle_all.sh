#!/bin/bash
# Sequentially oracle-verify all lint-ok tasks in chunks of 40, 12 concurrent each.
set -u
cd "$(dirname "$0")/.."
TOTAL=$(wc -l < specs/ok_tasks.txt | tr -d ' ')
NCHUNKS=$(( (TOTAL + 39) / 40 ))
echo "oracle pass: $TOTAL tasks in $NCHUNKS chunks"
for i in $(seq 0 $((NCHUNKS - 1))); do
  if [ -f "jobs/oracle-chunk-$i/result.json" ]; then
    echo "chunk $i already done, skipping"
    continue
  fi
  echo "=== chunk $i / $NCHUNKS ==="
  tools/run_oracle_batch.sh "$i"
done
echo ORACLE_PASS_COMPLETE
