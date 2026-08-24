#!/bin/bash
mkdir -p /logs/verifier
reward=0

TOKEN="df-token-8f3b21e9"

if python3 - <<'PY'
import sys
ty = open('/app/file_type.txt').read().strip().lower()
flag = open('/app/flag.txt').read().strip()
data = open('/app/evidence.bin','rb').read()
assert ty == 'png', ty
# Sanity: the hidden token really is in the trailing bytes of the evidence file
assert flag == 'df-token-8f3b21e9', flag
assert ('HIDDEN-TOKEN:' + flag) in data.decode('latin1')
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt