#!/usr/bin/env bash
set -euo pipefail

# Create the agent-facing rate limiter implementation and run it to produce
# /app/result.json.
cat > /app/rate_limiter.py <<'PY'
import json, math

data = json.load(open("/app/requests.json"))
limit = data["config"]["limit"]
window_sec = data["config"]["window_sec"]
ts = data["requests_ts"]

counts = {}
allowed = []
for t in ts:
    w = math.floor(t / window_sec)
    n = counts.get(w, 0)
    if n < limit:
        allowed.append(True)
        counts[w] = n + 1
    else:
        allowed.append(False)

with open("/app/result.json", "w") as f:
    json.dump({"allowed": allowed}, f)
PY
python3 /app/rate_limiter.py