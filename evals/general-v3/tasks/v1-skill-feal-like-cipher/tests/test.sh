#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/plaintext.bin" ] && [ -f "$APP/cipher.bin" ] && [ -f "$APP/cipher.json" ]; then
  if python3 - "$APP" <<'PYEOF'
import json, sys
base = sys.argv[1]
plain = open(base + '/plaintext.bin', 'rb').read()

def rot(x):
    return ((x << 2) | (x >> 6)) & 0xFF

def F(R, K):
    return [rot((R[i] + K[i]) & 0xFF) for i in range(4)]

def xorvec(a, b):
    return [a[i] ^ b[i] for i in range(4)]

KEYS = [[0x12,0x23,0x45,0x67],[0x89,0xAB,0xCD,0xEF],
        [0xFE,0xDC,0xBA,0x98],[0x76,0x54,0x32,0x10]]
L = list(plain[0:4]); R = list(plain[4:8])
for i in range(4):
    newL = R
    newR = xorvec(L, F(R, KEYS[i]))
    L, R = newL, newR
ct = bytes(L + R)
gotbin = open(base + '/cipher.bin', 'rb').read()
try:
    gotjson = json.load(open(base + '/cipher.json'))
except Exception:
    sys.exit(1)
ok = (gotbin == ct) and gotjson.get('plaintext') == plain.hex() and gotjson.get('ciphertext') == ct.hex()
sys.exit(0 if ok else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt