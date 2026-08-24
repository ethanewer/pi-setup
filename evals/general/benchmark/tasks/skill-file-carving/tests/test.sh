#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/carved.png ] && [ -f /app/carved.json ]; then
  if python3 - <<'PYEOF'
import json
blob = open('/app/blob.bin', 'rb').read()
sig = b'\x89PNG\r\n\x1a\n'
start = blob.index(sig)
iend = blob.index(b'IEND')
end = iend + 8
expected = blob[start:end]
got = open('/app/carved.png', 'rb').read()
if got != expected:
    raise SystemExit((len(got), len(expected)))
if got[:8] != sig:
    raise SystemExit('bad signature')
if got[-8:-4] != b'IEND':
    raise SystemExit('missing IEND')
if got[-12:-8] != b'\x00\x00\x00\x00':
    raise SystemExit('bad IEND length')
j = json.load(open('/app/carved.json'))
if j['offset'] != start:
    raise SystemExit((j, start))
if j['length'] != len(expected):
    raise SystemExit((j, len(expected)))
if j['valid_ending'] is not True:
    raise SystemExit(j)
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt