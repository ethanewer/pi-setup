#!/bin/bash
# Full oracle sweep of ALL tasks at concurrency $CON (default 8).
set -u
cd "$(dirname "$0")/.."
CON="${1:-8}"
python3 - <<PY
import json, pathlib
plan = json.load(open('specs/plan.json'))
allnames = sorted(t['name'] for t in plan['item_tasks'] + plan['skill_tasks'])
pathlib.Path('specs/all_tasks.txt').write_text('\n'.join(allnames) + '\n')
PY
TOTAL=$(wc -l < specs/all_tasks.txt | tr -d ' ')
NCHUNKS=$(( (TOTAL + 39) / 40 ))
echo "full oracle sweep: $TOTAL tasks in $NCHUNKS chunks @ concurrency $CON"
for i in $(seq 0 $((NCHUNKS - 1))); do
  JOB="oracle-full-$i"
  if [ -f "jobs/$JOB/result.json" ]; then continue; fi
  CHUNK=$(awk -v i="$i" 'NR > i*40 && NR <= (i+1)*40' specs/all_tasks.txt)
  ARGS=()
  while IFS= read -r name; do ARGS+=(-i "$name"); done <<< "$CHUNK"
  echo "=== full chunk $i / $NCHUNKS (${#ARGS[@]} names) ==="
  harbor run -p tasks -a oracle -y -o jobs --job-name "$JOB" -n "$CON" "${ARGS[@]}" 2>&1 | tail -3
done
echo FULL_ORACLE_SWEEP_COMPLETE
