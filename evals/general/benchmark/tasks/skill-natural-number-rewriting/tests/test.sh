#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/converted.txt ]; then
  if python3 - <<'EOF'
def fmt(n, base):
    if n == 0:
        return '0'
    digits = '0123456789abcdef'
    out = []
    while n > 0:
        out.append(digits[n % base])
        n //= base
    return ''.join(reversed(out))

expected = []
with open('/app/numbers.txt') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        value, from_base, to_base = line.split()
        n = int(value, int(from_base))
        expected.append(fmt(n, int(to_base)))

got = [g for g in open('/app/converted.txt').read().strip().split('\n') if g != '']
if got != expected:
    raise SystemExit((got, expected))
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt