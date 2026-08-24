#!/bin/bash
# Run oracle verification over lint-ok tasks in chunks of 40.
# Usage: tools/run_oracle_batch.sh <chunk-index>
set -u
cd "$(dirname "$0")/.."
IDX="$1"
LINES=$(cat specs/ok_tasks.txt)
CHUNK=$(echo "$LINES" | awk -v i="$IDX" 'NR > i*40 && NR <= (i+1)*40')
if [ -z "$CHUNK" ]; then
  echo "empty chunk $IDX"; exit 0
fi
ARGS=()
while IFS= read -r name; do
  ARGS+=(-i "$name")
done <<< "$CHUNK"
echo "chunk $IDX: ${#ARGS[@]} include args"
harbor run -p tasks -a oracle -y -o jobs --job-name "oracle-chunk-$IDX" -n 12 "${ARGS[@]}" 2>&1 | tail -25
