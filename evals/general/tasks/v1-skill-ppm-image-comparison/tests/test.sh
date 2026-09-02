#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/compare.py" ] && [ -f "$APP/diff.txt" ] && [ -f "$APP/a.ppm" ] && [ -f "$APP/b.ppm" ]; then
  agent_out=$(python3 "$APP/compare.py" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -n "$agent_out" ]; then
    expected=$(python3 - "$APP" <<'PY'
import sys
app = sys.argv[1]
def load(path):
    toks = []
    for line in open(path):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        toks += line.split()
    return toks
ta = load(app + '/a.ppm')
tb = load(app + '/b.ppm')
assert ta[0] == 'P3' and tb[0] == 'P3'
w = int(ta[1]); h = int(ta[2]); n = w * h
pa = [int(x) for x in ta[4:4 + n*3]]
pb = [int(x) for x in tb[4:4 + n*3]]
ndiff = 0; md = 0
for i in range(n):
    if pa[i*3] != pb[i*3] or pa[i*3+1] != pb[i*3+1] or pa[i*3+2] != pb[i*3+2]:
        ndiff += 1
for c in range(n*3):
    d = abs(pa[c] - pb[c])
    if d > md: md = d
print(f"{ndiff} {md}")
PY
    )
    if [ "$agent_out" = "$expected" ]; then
      reward=1
    fi
  fi
fi
printf '%s' "$reward" > /logs/verifier/reward.txt