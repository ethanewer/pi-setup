#!/bin/bash
set -euo pipefail

cat > /app/convert.py <<'EOF'
import json
from datetime import date, datetime, timedelta

data = json.load(open("/app/climate.json"))
out = []
for v in data["variables"]:
    unit, _, ref = v["units"].partition("since ")
    ref_s = ref.strip()
    dates = []
    td = None
    if unit.strip().startswith("day"):
        y, m, d = (int(x) for x in ref_s.split()[0].split("-"))
        td = timedelta(days=1)
        base = date(y, m, d)
        for off in v["offsets"]:
            dates.append((base + timedelta(days=off)).isoformat())
    elif unit.strip().startswith("hour"):
        y, m, d = (int(x) for x in ref_s.split()[0].split("-"))
        base = datetime(y, m, d)
        for off in v["offsets"]:
            dates.append((base + timedelta(hours=off)).date().isoformat())
    out.append({"name": v["name"], "dates": dates})

json.dump(out, open("/app/dates.json", "w"))
EOF

python3 /app/convert.py