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
d = json.load(open('/app/data.json'))
x = d["x"]; W1 = d["W1"]; b1 = d["b1"]; W2 = d["W2"][0]; b2 = d["b2"][0]
z1 = [W1[0][0]*x[0]+W1[0][1]*x[1]+b1[0], W1[1][0]*x[0]+W1[1][1]*x[1]+b1[1]]
h  = [max(0.0, v) for v in z1]
act = [v > 0 for v in h]
y = W2[0]*h[0] + W2[1]*h[1] + b2
got = json.load(open('/app/result.json'))
def f(v):
    return round(float(v), 6)
ok = (
    [f(v) for v in z1] == [f(v) for v in got["hidden_pre"]]
    and [f(v) for v in h] == [f(v) for v in got["hidden_post"]]
    and [bool(v) for v in act] == [bool(v) for v in got["active"]]
    and abs(y - float(got["output"])) < 1e-9
)
if not ok:
    raise SystemExit(1)
print("PASS"); raise SystemExit(0)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt