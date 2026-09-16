#!/usr/bin/env bash
# Acceptance census for the v4.1 wave: re-run the both-direction gate over every
# landed task, sharded, and record the observed rewards rather than the authors'
# self-reports. The suite's own history is why this exists -- 28 tasks were
# repaired in v3.4 because their reference solution could not pass, and a full
# oracle census found them where sampling would not.
set -uo pipefail
cd /home/ee/pi-setup/evals/general
OUT=/tmp/v41-census
SHARDS=${SHARDS:-4}
rm -rf "$OUT"; mkdir -p "$OUT"

python3 - <<'PY' > "$OUT/tasks.txt"
import json
slots=[x['name'] for x in json.load(open('specs/v41_slots.json'))]
import os
print('\n'.join(s for s in slots if os.path.isdir(f'tasks/{s}') and os.path.exists(f'tasks/{s}/task.toml')))
PY
n=$(wc -l < "$OUT/tasks.txt")
echo "=== [$(date -Is)] census over $n landed tasks, $SHARDS shards ==="

split -n r/$SHARDS -d "$OUT/tasks.txt" "$OUT/shard"
for s in "$OUT"/shard*; do
  ( while read -r t; do
      [ -n "$t" ] || continue
      bash tools/verify_new_task.sh "$t" >"$OUT/$t.log" 2>&1
      echo "$t rc=$?" >> "$OUT/rc.txt"
    done < "$s" ) &
done
wait

echo "=== [$(date -Is)] census complete ==="
sort "$OUT/rc.txt" | awk '{print} $2!="rc=0"{bad++} END{print "---"; print "passed: " NR-bad+0 " / " NR; if(bad) print "FAILED: " bad}'
