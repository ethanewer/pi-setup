#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
d = json.load(open('/app/answer.json'))
assert d.get('uses_gqa') is True
assert d.get('uses_rope') is True
assert d.get('uses_rmsnorm') is True
assert d.get('decoder_only') is True
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt