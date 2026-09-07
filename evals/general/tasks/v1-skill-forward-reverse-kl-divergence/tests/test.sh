#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/kl_divs.json ]; then
  if python3 - <<'EOF'
import json, math
p = json.load(open('/app/p.json'))
q = json.load(open('/app/q.json'))

def kl(a, b):
    return sum(0.0 if ai == 0 else ai * math.log(ai / bi) for ai, bi in zip(a, b))

expected = {
    "kl_fwd": round(kl(p, q), 4),
    "kl_rev": round(kl(q, p), 4),
}
out = json.load(open('/app/kl_divs.json'))
assert out == expected, (out, expected)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt