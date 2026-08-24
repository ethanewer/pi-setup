#!/bin/bash
set -euo pipefail

cat > /app/complex.py <<'PYEOF'
with open('/app/plex.txt') as f:
    lines = [ln.strip() for ln in f if ln.strip()]
a = complex(lines[0])
b = complex(lines[1])

s = a + b
p = a * b
ma = abs(a)
mb = abs(b)

out = []
out.append("sum_real={:.6f}".format(s.real))
out.append("sum_imag={:.6f}".format(s.imag))
out.append("product_real={:.6f}".format(p.real))
out.append("magnitude_a={:.6f}".format(ma))
out.append("magnitude_b={:.6f}".format(mb))
with open('/app/results.txt', 'w') as f:
    f.write(chr(10).join(out) + chr(10))
PYEOF

python3 /app/complex.py