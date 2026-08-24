#!/bin/bash
# Verifier for item-028-hard.
mkdir -p /logs/verifier
cd /app

# Regenerate the deterministic spec stream (spec.ml is the contract and must
# not be edited), then recompile the runtime from the (possibly modified)
# workspace source so we prove the source -- not a stale artifact -- is correct.
if command -v ocaml >/dev/null 2>&1; then
  ocaml spec.ml >/tmp/spec_out.txt 2>&1
fi

if [ ! -f runtime.c ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi
gcc -std=c99 -O2 runtime.c -o /tmp/runtime_g 2>/tmp/gerr.txt || { echo 0 > /logs/verifier/reward.txt; exit 0; }
/tmp/runtime_g >/tmp/gout.txt 2>&1

python3 - <<'PY'
RUNS = [(3, 0x41), (160, 0x42), (2, 0x43), (130, 0x44),
        (1, 0x45), (255, 0x21), (1, 0x46)]
want = b''
for n, v in RUNS:
    want += bytes([v]) * n

def checksum(b):
    s = 0
    for x in b:
        s = (s * 31 + x) & 0xFFFF
    return s & 0xFFFF

out = open('/app/out.dat', 'rb').read()
reward = 1 if (out == want and checksum(out) == checksum(want)) else 0
open('/logs/verifier/reward.txt', 'w').write('%d\n' % reward)
PY
exit 0