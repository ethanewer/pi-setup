#!/usr/bin/env bash
set -euo pipefail

cat > /app/shift.py <<'PYEOF'
import json

with open('/app/data.json') as f:
    data = json.load(f)

nu0 = float(data['laser_wavenumber_cm1'])
shifts = []
for line in data['lines']:
    wl = float(line['wavelength_nm'])
    shift = nu0 - 1e7 / wl
    shifts.append({'label': line['label'], 'shift_cm1': round(shift, 1)})

with open('/app/result.json', 'w') as f:
    json.dump({'shifts': shifts}, f)
PYEOF

python3 /app/shift.py