#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/output.txt ] && [ -f /app/program.bin ]; then
  if python3 - <<'PYEOF'
import struct

data = open('/app/program.bin', 'rb').read()
if len(data) % 12 != 0:
    raise SystemExit('program.bin not whole instructions')
reg = [0] * 8
out = []
for i in range(len(data) // 12):
    op, ra, rb = struct.unpack_from('<III', data, i * 12)
    if op == 1:
        reg[ra] = rb
    elif op == 2:
        reg[ra] = (reg[ra] + reg[rb]) & 0xFFFFFFFF
    elif op == 3:
        reg[ra] = (reg[ra] - reg[rb]) & 0xFFFFFFFF
    elif op == 4:
        out.append(str(reg[ra]))
    elif op == 5:
        reg[ra] = reg[rb]
    else:
        raise SystemExit('unknown opcode %d' % op)

expected = '\n'.join(out) + '\n'
got = open('/app/output.txt', 'r').read().replace('\r\n', '\n')
if got != expected:
    raise SystemExit((got, expected))
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt