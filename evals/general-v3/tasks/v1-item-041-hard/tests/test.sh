#!/bin/bash
# Verifier for item-041-hard. Rebuilds the fixed project from scratch, runs
# it through the runner, and checks the ABI + the emitted frame hash.
# Always writes /logs/verifier/reward.txt (0..1).
set -uo pipefail

mkdir -p /logs/verifier
reward=0

abort() { echo "$reward" > /logs/verifier/reward.txt; exit 0; }

cd /app || abort

python3 - <<'PY' > /tmp/elf_check.json
import struct, json
try:
    d = open('/app/out.elf','rb').read(20)
    ok = d[4] == 1 and d[5] == 2 and struct.unpack('>H', d[18:20])[0] == 8
    print(json.dumps({"ok": bool(ok), "class": d[4], "data": d[5], "machine": struct.unpack('>H', d[18:20])[0]}))
except Exception as e:
    print(json.dumps({"ok": False, "error": str(e)}))
PY
elf_ok=$(python3 -c "import json;print('1' if json.load(open('/tmp/elf_check.json'))['ok'] else '0')")

# Rebuild from the agent's (fixed) sources deterministically.
if ! make clean >/tmp/make_clean.log 2>&1; then abort; fi
if ! make >/tmp/make.log 2>&1; then abort; fi
node tools/run.js out.elf > /tmp/rebuilt.dat 2>/tmp/run.log
node_rc=$?

size=0; hash="x"
if [ -s /tmp/rebuilt.dat ]; then
  size=$(wc -c < /tmp/rebuilt.dat 2>/dev/null || echo 0)
  hash=$(python3 -c "import hashlib;print(hashlib.sha256(open('/tmp/rebuilt.dat','rb').read()).hexdigest())" 2>/dev/null || echo "x")
fi

if [ "$size" = "2054" ] && [ "$hash" = "7a8e00efcf4625b02cff2c49a58a81a48ffbe67eee843e3a25f36ff2b100ac9a" ]; then
  frame_ok=1
else
  frame_ok=0
fi

# Also require the left-behind /app/out.dat to be the final frame (robustness).
left_ok=0
if [ -f /app/out.dat ]; then
  lh=$(python3 -c "import hashlib;print(hashlib.sha256(open('/app/out.dat','rb').read()).hexdigest())" 2>/dev/null || echo x)
  ls=$(wc -c < /app/out.dat 2>/dev/null || echo 0)
  if [ "$ls" = "2054" ] && [ "$lh" = "7a8e00efcf4625b02cff2c49a58a81a48ffbe67eee843e3a25f36ff2b100ac9a" ]; then
    left_ok=1
  fi
fi

if [ "$elf_ok" = "1" ] && [ "$frame_ok" = "1" ]; then
  reward=1
elif [ "$elf_ok" = "1" ] && [ "$left_ok" = "1" ]; then
  reward=0.9
elif [ "$elf_ok" = "1" ] && [ "$frame_ok" = "0" ] && [ "$node_rc" != "0" ]; then
  reward=0.4   # ABI ok but runner/emission still failing
elif [ "$elf_ok" = "1" ] && [ "$frame_ok" = "0" ]; then
  reward=0.5   # right ABI, wrong frame content
elif [ "$frame_ok" = "1" ]; then
  reward=0.5   # right frame but not a big-endian MIPS ELF
fi

echo "$reward" > /logs/verifier/reward.txt