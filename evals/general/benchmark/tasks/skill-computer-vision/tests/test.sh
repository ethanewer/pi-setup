#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/report.txt ] && [ -f /app/image.pgm ]; then
  if python3 - <<'PYEOF'
lines = [l for l in open('/app/image.pgm').read().splitlines() if l.strip()]
assert lines[0] == 'P2'
w, h = map(int, lines[1].split())
values = [int(v) for v in ' '.join(lines[3:]).split()]
assert len(values) == w * h

bright = sum(1 for v in values if v >= 128)
mean = sum(values) / len(values)

expected = {
    'width': w, 'height': h,
    'bright': bright,
    'mean': round(mean, 2),
}
got = {}
for l in open('/app/report.txt'):
    l = l.strip()
    if not l: continue
    k, v = l.split('=')
    got[k.strip()] = v.strip()
assert int(got['width']) == expected['width'], got
assert int(got['height']) == expected['height'], got
assert int(got['bright']) == expected['bright'], got
assert abs(float(got['mean']) - expected['mean']) < 1e-9, got
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt