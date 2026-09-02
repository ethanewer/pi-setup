#!/usr/bin/env bash
set -euo pipefail

cat > /app/revcomp.py <<'PY'
import json

comp = str.maketrans("ACGT", "TGCA")
with open("/app/data.json") as f:
    data = json.load(f)
result = {"complements": [s.translate(comp)[::-1] for s in data["sequences"]]}
with open("/app/result.json", "w") as f:
    json.dump(result, f)
PY

python3 /app/revcomp.py