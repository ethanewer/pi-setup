#!/bin/bash
set -euo pipefail

cat > /app/leaderboard.py <<'EOF'
import csv, json

rows = []
with open('/app/leaderboard.csv') as f:
    for r in csv.DictReader(f):
        avg = round((float(r['task_a']) + float(r['task_b']) + float(r['task_c'])) / 3.0, 2)
        rows.append((r['model'], avg))

# stable sort descending by avg
rows.sort(key=lambda x: x[1], reverse=True)
top_model, top_score = rows[0]

result = {
    "top_model": top_model,
    "top_score": top_score,
    "ranking": [[name, avg] for name, avg in rows],
}
with open('/app/mteb.json', 'w') as f:
    json.dump(result, f)
EOF

python3 /app/leaderboard.py