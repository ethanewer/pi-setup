#!/bin/bash
set -euo pipefail

cat > /app/dna.py <<'EOF'
mapping = {'A': 'T', 'T': 'A', 'C': 'G', 'G': 'C'}
with open('/app/dna.txt') as f:
    seq = f.read().strip()

comp = ''.join(mapping[c] for c in seq)
gc = seq.count('G') + seq.count('C')
pct = round(100.0 * gc / len(seq), 2)

with open('/app/biochem.txt', 'w') as f:
    f.write(f"complement:{comp}\n")
    f.write(f"gc_pct:{pct}\n")
EOF

python3 /app/dna.py