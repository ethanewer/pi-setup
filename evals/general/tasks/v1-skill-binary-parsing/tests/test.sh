#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/data.bin" ] && [ -f "$APP/parsed.json" ]; then
  if python3 - "$APP" <<'PYEOF'
import struct, json, sys
base = sys.argv[1]
data = open(base + '/data.bin', 'rb').read()
if data[:4] != b'DPAR':
    sys.exit(1)
N = struct.unpack('<I', data[4:8])[0]
if len(data) != 8 + N * 6:
    sys.exit(1)
s0 = 0; s1 = 0; x = 0; off = 8
for i in range(N):
    typ, val = struct.unpack_from('<Hi', data, off)
    off += 6
    if typ == 0: s0 += val
    elif typ == 1: s1 += val
    x ^= val
exp = {'count': N, 'sum_type0': s0, 'sum_type1': s1, 'xor_all': x}
try:
    got = json.load(open(base + '/parsed.json'))
except Exception:
    sys.exit(1)
sys.exit(0 if got == exp else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt