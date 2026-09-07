#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import importlib.util, json
spec = importlib.util.spec_from_file_location("fbox_mod", "/app/fbox.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
fbox = mod.fbox
def rot(x):
    return ((x << 2) | (x >> 6)) & 0xFF
def ref(a, b):
    return [rot((a[i] + b[i]) & 0xFF) for i in range(4)]
fixed = [([0, 0, 0, 0], [1, 2, 3, 4]), ([255, 255, 255, 255], [1, 1, 1, 1]),
         ([18, 52, 86, 120], [171, 205, 239, 1])]
for a, b in fixed:
    assert fbox(a, b) == ref(a, b), (a, b)
v = json.load(open('/app/vectors.json'))
out = json.load(open('/app/answers.json'))
assert out['input']['r'] == v['r'] and out['input']['k'] == v['k'], out['input']
assert out['output'] == ref(v['r'], v['k']), out['output']
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt