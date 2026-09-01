#!/bin/bash
set -euo pipefail

cat > /app/report.py <<'EOF'
from fetch_pdb import fetch_pdb

d = fetch_pdb('3abc')
residues = d['struct']['n_residues']
atoms = sum(e['n_atoms'] for e in d['entities'])

with open('/app/answer.txt', 'w') as f:
    f.write(f"atoms {atoms} residues {residues}\n")
EOF

python3 /app/report.py