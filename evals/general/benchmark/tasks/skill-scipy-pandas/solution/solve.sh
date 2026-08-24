#!/bin/bash
set -euo pipefail

cat > /app/analyze.py <<'EOF'
import json
import pandas as pd
from scipy.signal import find_peaks

df = pd.read_csv('/app/sensors.csv')
per_sensor = []
for sid in sorted(df['sensor_id'].unique()):
    sub = df[df['sensor_id'] == sid].sort_values('time_ms')
    values = sub['value'].to_numpy()
    peaks, _ = find_peaks(values, prominence=10, distance=3)
    per_sensor.append({
        "sensor_id": int(sid),
        "mean": float(round(sub['value'].mean(), 2)),
        "median": float(round(sub['value'].median(), 2)),
        "peak_count": int(len(peaks)),
    })

with open('/app/results.json', 'w') as f:
    json.dump({"per_sensor": per_sensor}, f)
EOF

python3 /app/analyze.py