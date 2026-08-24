#!/bin/bash
mkdir -p /logs/verifier

reward=0
if [ -f /app/results.txt ]; then
  if python3 - <<'PYEOF'
with open('/app/plex.txt') as f:
    lines = [ln.strip() for ln in f if ln.strip()]
a = complex(lines[0]); b = complex(lines[1])
s = a + b; p = a * b
expected = {
    'sum_real': float("{:.6f}".format(s.real)),
    'sum_imag': float("{:.6f}".format(s.imag)),
    'product_real': float("{:.6f}".format(p.real)),
    'magnitude_a': float("{:.6f}".format(abs(a))),
    'magnitude_b': float("{:.6f}".format(abs(b))),
}
got = {}
for ln in open('/app/results.txt'):
    ln = ln.strip()
    if not ln:
        continue
    k, v = ln.split('=')
    got[k.strip()] = float(v)
assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt