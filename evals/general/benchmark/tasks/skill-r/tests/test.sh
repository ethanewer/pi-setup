#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/summary.csv ]; then
  if python3 - <<'PY'
import sys, collections
rows = collections.defaultdict(list)
for l in open('/app/stats.csv'):
    l = l.strip()
    if not l:
        continue
    p = l.split(',')
    if p[0].strip() == 'group':
        continue
    rows[p[0].strip()].append(float(p[1]))
expected = {k: round(sum(v)/len(v), 2) for k, v in rows.items()}
got = {}
for l in open('/app/summary.csv'):
    l = l.strip()
    if not l:
        continue
    p = l.split(',')
    if len(p) < 2:
        continue
    g = p[0].strip()
    if g == 'group':
        continue
    try:
        got[g] = round(float(p[1].strip()), 2)
    except ValueError:
        continue
if got == expected:
    print("PASS"); sys.exit(0)
print("FAIL got=%r exp=%r" % (got, expected)); sys.exit(1)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt