#!/usr/bin/env bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PY'
import json, sys
got = json.load(open("/app/result.json"))
items = [(s["label"], round(float(s["shift_cm1"]), 1)) for s in got.get("shifts", [])]
ok = items == [("A", 1703.0), ("B", 713.8)]
sys.exit(0 if ok else 1)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt