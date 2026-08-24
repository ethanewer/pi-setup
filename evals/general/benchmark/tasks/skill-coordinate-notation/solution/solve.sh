#!/bin/bash
set -euo pipefail

cat > /app/convert.py <<'PYEOF'
import re

def parse(dms):
    m = re.match(r"^(?P<d>[-+]?\d+(?:\.\d+)?)°\s*(?P<min>\d+(?:\.\d+)?)['′]?\s*(?P<sec>\d+(?:\.\d+)?)?[\"″]?\s*(?P<hemi>[NSEW])$", dms.strip())
    if not m:
        raise ValueError("bad DMS: %r" % dms)
    d = float(m.group('d'))
    mi = float(m.group('min'))
    sec = float(m.group('sec')) if m.group('sec') else 0.0
    hemi = m.group('hemi')
    value = d + mi / 60.0 + sec / 3600.0
    if hemi in ('S', 'W'):
        value = -value
    return value

coords = []
with open('/app/coords.txt') as f:
    for line in f:
        line = line.strip()
        if line:
            coords.append(parse(line))

with open('/app/decimal.txt', 'w') as f:
    for c in coords:
        f.write("{:.6f}\n".format(c))
PYEOF

python3 /app/convert.py