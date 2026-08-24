#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/jobs.txt" ] && [ -f "$APP/queue.json" ]; then
  if python3 - "$APP" <<'PYEOF'
import json, sys
base = sys.argv[1]
jobs = []
for line in open(base + '/jobs.txt'):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    jid, arr, bur = line.split('\t')
    jobs.append((jid, int(arr), int(bur)))
work = sorted(enumerate(jobs), key=lambda t: (t[1][1], t[0]))
time = 0; waits = []
for idx, (jid, arr, bur) in work:
    start = max(time, arr)
    comp = start + bur
    waits.append(start - arr)
    time = comp
avg = round(sum(waits) / len(waits), 2)
exp = {"jobs": len(jobs), "avg_wait": avg, "completion_time": time}
try:
    got = json.load(open(base + '/queue.json'))
except Exception:
    sys.exit(1)
ok = got.get('jobs') == exp['jobs'] and got.get('completion_time') == exp['completion_time']
if ok:
    try:
        ok = abs(float(got['avg_wait']) - exp['avg_wait']) < 1e-6
    except Exception:
        ok = False
sys.exit(0 if ok else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt