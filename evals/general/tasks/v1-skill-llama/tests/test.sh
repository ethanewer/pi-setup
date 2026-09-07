#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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