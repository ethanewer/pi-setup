#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/cifar_info.json ]; then
  if python3 - <<'PYEOF'
import json
exp = {
    "classes": ["airplane","automobile","bird","cat","deer","dog","frog","horse","ship","truck"],
    "num_classes": 10,
    "image_shape": [32, 32, 3],
    "num_train": 50000,
    "num_test": 10000,
}
got = json.load(open('/app/cifar_info.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt