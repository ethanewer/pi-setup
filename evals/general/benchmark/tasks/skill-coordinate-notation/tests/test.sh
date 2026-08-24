#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import re, math
def parse(dms):
    m = re.match(r"^(?P<d>[-+]?\d+(?:\.\d+)?)°\s*(?P<min>\d+(?:\.\d+)?)['\u2032]?\s*(?P<sec>\d+(?:\.\d+)?)?[\"\u2033]?\s*(?P<hemi>[NSEW])$", dms.strip())
    if not m:
        raise ValueError('bad DMS: %r' % dms)
    d = float(m.group('d'))
    mi = float(m.group('min'))
    sec = float(m.group('sec')) if m.group('sec') else 0.0
    val = d + mi / 60.0 + sec / 3600.0
    if m.group('hemi') in ('S', 'W'):
        val = -val
    return val
coords = []
with open('/app/coords.txt') as f:
    for line in f:
        line = line.strip()
        if line:
            coords.append(parse(line))
got = [float(x) for x in open('/app/decimal.txt').read().split()]
assert len(got) == len(coords), (len(got), len(coords))
for g, c in zip(got, coords):
    assert abs(g - c) <= 1e-6, (g, c)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt