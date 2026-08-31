#!/bin/bash
# Fleet driver v2: batches2, resume-safe (skips competencies already done per RESULT lines).
set -u
ROOT=/Users/ethanewer/pi-setup/evals/general-v2
cd "$ROOT"
CONC=${1:-3}

# function: is a competency done?
python3 - <<'PYEOF' > /tmp/done_cids.txt
import json, glob, re
done = set()
for f in glob.glob('tmp/second-tasks/*/agent.out'):
    for line in open(f, errors='ignore'):
        if line.startswith('RESULT'):
            m = re.search(r'"cid":"(C-[^"]+)".*?"oracle_reward":\s*1\.0', line.replace("'", '"'))
            if m: done.add(m.group(1))
print('\n'.join(sorted(done)))
PYEOF

for f in tmp/second-tasks/batches2/batch_*.json; do
  bn=$(basename "$f" .json)
  # skip if ALL competencies in this batch are done
  if python3 - "$f" /tmp/done_cids.txt <<'PYEOF'
import json, sys
batch = json.load(open(sys.argv[1]))
done = set(open(sys.argv[2]).read().split())
sys.exit(0 if all(c['id'] in done for c in batch) else 1)
PYEOF
  then continue; fi
  bash tmp/second-tasks/author_batch2.sh "$f" &
  while [ "$(jobs -r | wc -l)" -ge $CONC ]; do wait -n; done
done
wait
echo "FLEET2_COMPLETE"
