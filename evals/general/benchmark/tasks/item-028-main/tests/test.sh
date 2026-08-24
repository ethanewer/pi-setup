#!/bin/bash
# Verifier for item-028-main. Checks /app/out.dat recovery + checksum.
mkdir -p /logs/verifier

python3 - <<'PY'
import sys
RUNS = [(3, 0x41), (160, 0x42), (2, 0x43), (130, 0x44),
        (1, 0x45), (255, 0x21), (1, 0x46)]
want = b''
for n, v in RUNS:
    want += bytes([v]) * n

try:
    with open('/app/out.dat', 'rb') as f:
        out = f.read()
except FileNotFoundError:
    print('ERR out.dat missing')
    print(0, file=open('/logs/verifier/reward.txt', 'w'))
    sys.exit(0)

def checksum(b):
    s = 0
    for x in b:
        s = (s * 31 + x) & 0xFFFF
    return s & 0xFFFF

reward = 1 if (out == want) and checksum(out) == checksum(want) else 0
open('/logs/verifier/reward.txt', 'w').write(('%d' % reward) + '\n')
print('reward=%d out_len=%d want_len=%d' % (reward, len(out), len(want)))
PY
exit 0