FROM bench-base:node-22

WORKDIR /app

# Generate the bytecode program deterministically with python3 (available in the base image).
RUN python3 - <<'PYEOF'
import struct

I = []  # list of (opcode, rA, rB)

def loadi(r, val): I.append((1, r, val))
def add(rA, rB):   I.append((2, rA, rB))
def sub(rA, rB):   I.append((3, rA, rB))
def pr(r):         I.append((4, r, 0))
def mov(dst, src): I.append((5, dst, src))

# Fibonacci: print 0, 1, 1, 2, 3, 5, 8, 13, 21, 34
loadi(0, 0)
loadi(1, 1)
pr(0)
pr(1)
for _ in range(8):
    loadi(2, 0)   # r2 = 0
    add(2, 0)     # r2 = r0
    add(2, 1)     # r2 = r0 + r1
    pr(2)
    mov(0, 1)
    mov(1, 2)

with open('/app/program.bin', 'wb') as f:
    for op, ra, rb in I:
        f.write(struct.pack('<III', op, ra, rb))
PYEOF
