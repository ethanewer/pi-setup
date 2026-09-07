#!/usr/bin/env bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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