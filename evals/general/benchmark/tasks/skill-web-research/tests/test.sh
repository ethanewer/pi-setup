#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/research.json ]; then
  if python3 - <<'EOF'
import json
with open("/app/research.json") as f:
    r = json.load(f)
if not isinstance(r, dict):
    raise SystemExit("must be an object")
if r.get("title") != "Harbor Annual Report":
    raise SystemExit(r)
if r.get("revenue") != "1250":
    raise SystemExit(r)
if r.get("founded") != "1998":
    raise SystemExit(r)
if r.get("headquarters") != "Austin":
    raise SystemExit(r)
if not all(isinstance(v, str) for v in r.values()):
    raise SystemExit(r)
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt