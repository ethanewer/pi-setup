#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/biochem.txt ]; then
  if python3 - <<'EOF'
mapping = {'A': 'T', 'T': 'A', 'C': 'G', 'G': 'C'}
with open('/app/dna.txt') as f:
    seq = f.read().strip()

comp = ''.join(mapping[c] for c in seq)
gc = seq.count('G') + seq.count('C')
pct = round(100.0 * gc / len(seq), 2)
expected = f"complement:{comp}\ngc_pct:{pct}"

with open('/app/biochem.txt') as f:
    got = f.read().strip()
if got != expected:
    raise SystemExit((got, expected))
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt