#!/bin/bash
set -euo pipefail

cat > /app/interpreter.py <<'EOF'
import re, json

x = y = 0.0
with open('/app/move.gcode') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith(';'):
            continue
        # strip inline comment
        line = re.sub(r';.*', '', line)
        m = re.match(r'G\d+\s+(.*)$', line)
        if not m:
            continue
        xm = re.search(r'X([-+0-9.]+)', m.group(1))
        ym = re.search(r'Y([-+0-9.]+)', m.group(1))
        if xm: x = float(xm.group(1))
        if ym: y = float(ym.group(1))

with open('/app/final_pos.json', 'w') as f:
    json.dump({"x": round(x, 3), "y": round(y, 3)}, f)
EOF
python3 /app/interpreter.py