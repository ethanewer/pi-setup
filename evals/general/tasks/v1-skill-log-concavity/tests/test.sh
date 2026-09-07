#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'EOF'
import json
arrays={"array1":[2,4,8,16,32],"array2":[1,5,6,10]}
def is_lc(a):
    for k in range(1,len(a)-1):
        if a[k]**2 < a[k-1]*a[k+1]:
            return False
    return True
exp={f"{name}_log_concave": is_lc(a) for name,a in arrays.items()}
got=json.load(open('/app/answer.json'))
for k,v in exp.items():
    if str(got.get(k)).strip().lower() != str(v).lower():
        raise SystemExit("bad %s" % k)
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt