#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/decode.json ]; then
  if python3 - <<'PYEOF'
import json
FUNCT = {0x20: 'add', 0x22: 'sub'}
OPCODES = {0x08: 'addi', 0x23: 'lw'}
def decode(word):
    opcode = (word >> 26) & 0x3f
    if opcode == 0:
        funct = word & 0x3f
        if funct in FUNCT:
            return {"word": hex(word), "type": "R", "format": FUNCT[funct],
                    "rd": (word >> 11) & 0x1f, "rs": (word >> 21) & 0x1f,
                    "rt": (word >> 16) & 0x1f, "shamt": (word >> 6) & 0x1f}
        return {"word": hex(word), "type": "R", "format": "unknown", "opcode": opcode}
    if opcode in OPCODES:
        return {"word": hex(word), "type": "I", "format": OPCODES[opcode],
                "rs": (word >> 21) & 0x1f, "rt": (word >> 16) & 0x1f, "imm": word & 0xffff}
    return {"word": hex(word), "type": "I", "format": "unknown", "opcode": opcode}
words = [int(ln.strip(), 16) for ln in open('/app/instructions.txt') if ln.strip()]
exp = [decode(w) for w in words]
got = json.load(open('/app/decode.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt