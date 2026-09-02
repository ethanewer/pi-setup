#!/usr/bin/env bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PY'
import json, sys
comp = str.maketrans("ACGT", "TGCA")
data = json.load(open("/app/data.json"))
exp = [s.translate(comp)[::-1] for s in data["sequences"]]
got = json.load(open("/app/result.json"))
ok = got.get("complements") == exp
sys.exit(0 if ok else 1)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt