#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/migrated.json ]; then
  if python3 - <<'EOF'
import json
exp=[]
for line in open('/app/events_v1.jsonl'):
    line=line.strip()
    if not line: continue
    try: r=json.loads(line)
    except json.JSONDecodeError: continue
    if not all(k in r for k in ("time","user_id","event","amount")): continue
    exp.append({"timestamp":r["time"],"customer":"user_"+str(r["user_id"]),"kind":r["event"],"amount_cents":int(round(r["amount"]*100))})
got=json.load(open('/app/migrated.json'))
if got != exp:
    raise SystemExit("migration mismatch")
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt