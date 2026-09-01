#!/bin/bash
set -euo pipefail

cat > /app/find.py <<'EOF'
import re, json

with open("/app/words.txt") as f:
    words = [w.strip() for w in f if w.strip()]

matched = []
letters = {}
pat = re.compile(r"(\w)\1")
for w in words:
    m = pat.search(w)
    if m:
        matched.append(w)
        letters[w] = m.group(1)

with open("/app/doubles.json", "w") as f:
    json.dump({"matched": matched, "letters": letters}, f)
EOF

python3 /app/find.py