#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import os, json
src = '/app/loose'
dst = '/app/organized'
# loose must be empty
leftover = [n for n in os.listdir(src)]
assert not leftover, leftover
# gather actual files by ext
actual = {}
for ext in os.listdir(dst):
    d = os.path.join(dst, ext)
    if os.path.isdir(d):
        names = sorted(n for n in os.listdir(d) if os.path.isfile(os.path.join(d, n)))
        if names:
            actual[ext] = names
manifest = json.load(open('/app/manifest.json'))
assert manifest == actual, (manifest, actual)
# every file extension must match its folder
for ext, names in actual.items():
    for n in names:
        got = os.path.splitext(n)[1].lstrip('.')
        assert got == ext, (n, got, ext)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt