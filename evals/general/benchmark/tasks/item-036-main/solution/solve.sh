#!/bin/bash
set -euo pipefail

cat > /app/transform.py <<'PYEOF'
import re
lines = open('/app/data.csv', 'rb').read().splitlines()
out = []
rx = re.compile(rb'^(\d+),(\d{4})(\d{2})(\d{2}),(-?[\d.]+)$')
for ln in lines:
    m = rx.match(ln)
    if not m:
        raise SystemExit('bad input line: %r' % (ln,))
    out.append(b'%s,%s-%s-%s,%s' % (m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)))
with open('/app/out.csv', 'wb') as f:
    f.write(b'\n'.join(out) + b'\n')

with open('/app/macro_recipe.txt', 'w') as f:
    f.write(':%s/\\\\v([0-9]{4})([0-9]{2})([0-9]{2})/\\\\1-\\\\2-\\\\3/\n')
    f.write('single-row operation: 1 substitute command token\n')
print('wrote /app/out.csv')
PYEOF

python3 /app/transform.py