#!/bin/bash
set -euo pipefail

cat > /app/parse.py <<'EOF'
import json

out = []
with open('/app/people.dat') as f:
    for line in f:
        line = line.rstrip('\n')
        out.append({
            "id": int(line[0:4]),
            "name": line[4:16].strip(),
            "age": int(line[16:19].strip()),
            "city": line[19:29].strip(),
        })

with open('/app/records.json','w') as f:
    json.dump(out, f)
EOF
python3 /app/parse.py