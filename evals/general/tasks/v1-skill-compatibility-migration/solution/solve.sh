#!/bin/bash
set -euo pipefail

cat > /app/migrate.py <<'EOF'
import json

out = []
with open("/app/events_v1.jsonl") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not all(k in r for k in ("time", "user_id", "event", "amount")):
            continue
        out.append({
            "timestamp": r["time"],
            "customer": "user_" + str(r["user_id"]),
            "kind": r["event"],
            "amount_cents": int(round(r["amount"] * 100)),
        })

json.dump(out, open("/app/migrated.json", "w"))
EOF

python3 /app/migrate.py