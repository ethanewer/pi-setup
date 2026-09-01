#!/bin/bash
# Verifier for item-041-main. Rebuilds the fixed project from scratch, runs it
# through the VM runner, and checks the ABI + the emitted frame hash.
# Always writes /logs/verifier/reward.txt (0..1).
set -uo pipefail

mkdir -p /logs/verifier
reward=0

abort() { echo "$reward" > /logs/verifier/reward.txt; exit 0; }

cd /app || abort

# --- ABI check on the left-behind artifact ---
python3 - <<'PYEOF' > /tmp/elf_check.json
import struct, json
try:
    d = open('/app/out.elf','rb').read(20)
    ok = d[4] == 1 and d[5] == 2 and struct.unpack('>H', d[18:20])[0] == 8
    print(json.dumps({"ok": bool(ok), "cls": d[4], "data": d[5], "machine": struct.unpack('>H', d[18:20])[0]}))
except Exception as e:
    print(json.dumps({"ok": False, "error": str(e)}))
PYEOF
elf_ok=$(python3 -c "import json;print('1' if json.load(open('/tmp/elf_check.json'))['ok'] else '0')")

# Deterministic rebuild from the agent's (fixed) sources.
if ! make clean >/tmp/make_clean.log 2>&1; then abort; fi
if ! make >/tmp/make.log 2>&1; then abort; fi
node tools/run.js out.elf > /tmp/rebuilt.dat 2>/tmp/run.log
node_rc=$?

size=0; hash="x"
if [ -s /tmp/rebuilt.dat ]; then
  size=$(wc -c < /tmp/rebuilt.dat 2>/dev/null || echo 0)
  hash=$(python3 -c "import hashlib;print(hashlib.sha256(open('/tmp/rebuilt.dat','rb').read()).hexdigest())" 2>/dev/null || echo x)
fi

frame_ok=0
if [ "$size" = "1542" ] && [ "$hash" = "f84539f45492d43030fbb741f8dc281145d28f6be9665c2e9b1104c778126688" ]; then
  frame_ok=1
fi

# Also require the left-behind /app/out.dat to be the correct frame.
left_ok=0
if [ -f /app/out.dat ]; then
  lh=$(python3 -c "import hashlib;print(hashlib.sha256(open('/app/out.dat','rb').read()).hexdigest())" 2>/dev/null || echo x)
  ls=$(wc -c < /app/out.dat 2>/dev/null || echo 0)
  if [ "$ls" = "1542" ] && [ "$lh" = "f84539f45492d43030fbb741f8dc281145d28f6be9665c2e9b1104c778126688" ]; then
    left_ok=1
  fi
fi

if [ "$elf_ok" = "1" ] && [ "$frame_ok" = "1" ]; then
  reward=1
elif [ "$elf_ok" = "1" ] && [ "$left_ok" = "1" ]; then
  reward=0.9
elif [ "$frame_ok" = "1" ]; then
  reward=0.5        # correct frame but not a big-endian MIPS ELF
elif [ "$elf_ok" = "1" ]; then
  reward=0.5        # right ABI, but emitted frame still wrong
elif [ "$node_rc" != "0" ]; then
  reward=0.3
fi

echo "$reward" > /logs/verifier/reward.txt
