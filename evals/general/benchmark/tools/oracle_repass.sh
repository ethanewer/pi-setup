#!/bin/bash
# Re-oracle tasks in $1 using chunked harbor runs (40 per chunk, 12 concurrent).
set -u
cd "$(dirname "$0")/.."
LIST="$1"
TOTAL=$(wc -l < "$LIST" | tr -d ' ')
NCHUNKS=$(( (TOTAL + 39) / 40 ))
echo "re-oracle: $TOTAL tasks in $NCHUNKS chunks"
for i in $(seq 0 $((NCHUNKS - 1))); do
  JOB="oracle-re-${LIST##*/}-$i"
  if [ -f "jobs/$JOB/result.json" ]; then continue; fi
  CHUNK=$(awk -v i="$i" 'NR > i*40 && NR <= (i+1)*40' "$LIST")
  ARGS=()
  while IFS= read -r name; do ARGS+=(-i "$name"); done <<< "$CHUNK"
  echo "=== chunk $i / $NCHUNKS (${#ARGS[@]} names) ==="
  harbor run -p tasks -a oracle -y -o jobs --job-name "$JOB" -n 12 "${ARGS[@]}" 2>&1 | tail -3
done
echo REORACLE_COMPLETE
