#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.csv ]; then
  if python3 - <<'PY'
lines = [l.strip() for l in open("/app/result.csv") if l.strip()]
if len(lines) < 2:
    raise SystemExit("missing value line")
try:
    val = float(lines[1])
except Exception:
    raise SystemExit("bad value line")
if abs(val - 10.0) > 0.3:
    raise SystemExit(val)
print("PASS"); raise SystemExit(0)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt