#!/usr/bin/env bash
set -euo pipefail

# Oracle: install the real solver and RUN it on the provided visible spec to
# produce /app/answer.json. Never reads /tests. Uses literal /app paths.

cp /solution/solver.py /app/solve.py
chmod +x /app/solve.py

python3 /app/solve.py /app/spec.json /app/answer.json

n_cases="$(python3 - <<'PY'
import json
spec = json.load(open('/app/spec.json'))
print(len(spec.get('cases', [])))
PY
)"

echo "solved ${n_cases} visible cases -> /app/answer.json" >&2