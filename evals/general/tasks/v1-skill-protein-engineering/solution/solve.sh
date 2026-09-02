#!/bin/bash
set -euo pipefail

cat > /app/peptide_mass.py <<'PYEOF'
import json

residue_mass = {
    'A': 71.03711,
    'C': 103.00919,
    'E': 129.04259,
}
water_mass = 18.01056
peptide = 'ACE'
mass = sum(residue_mass[ch] for ch in peptide) + water_mass

with open('/app/molecule.json', 'w') as f:
    json.dump({'peptide': peptide, 'mass_da': mass}, f)
PYEOF

python3 /app/peptide_mass.py
echo "wrote /app/molecule.json"