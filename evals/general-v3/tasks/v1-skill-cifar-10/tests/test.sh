#!/bin/bash
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