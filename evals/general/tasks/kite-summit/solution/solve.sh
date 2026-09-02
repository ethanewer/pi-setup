#!/usr/bin/env bash
# Oracle solution for kite-summit. Builds every deliverable by doing the work.
set -euo pipefail

echo "== kite-summit oracle: producing deliverables =="

# ---------------------------------------------------------------- Subtask 1
# Generate the isqrt+Fibonacci(@2^32) operator network as /app/gate_net.txt and
# write /app/gate_validate.py.
python3 - <<'PY'
MASK = 0xFFFFFFFF
M = 1 << 32

class Net:
    def __init__(self):
        self.nodes = []      # list of (op, args)
        self.out = None
    def raw(self, op, args):
        self.nodes.append((op, args))
        return len(self.nodes) - 1
    def IN(self):    return self.raw('IN', [])
    def CONST(self, v):    return self.raw('CONST', [int(v) & MASK])
    def ADD(self, a, b):   return self.raw('ADD', [a, b])
    def SUB(self, a, b):   return self.raw('SUB', [a, b])
    def MUL(self, a, b):   return self.raw('MUL', [a, b])
    def SHL(self, a, k):   return self.raw('SHL', [a, int(k)])
    def SHR(self, a, k):   return self.raw('SHR', [a, int(k)])
    def AND(self, a, b):   return self.raw('AND', [a, b])
    def OR(self, a, b):    return self.raw('OR', [a, b])
    def XOR(self, a, b):   return self.raw('XOR', [a, b])
    def NOT(self, a):      return self.raw('NOT', [a])
    def MUX(self, c, x, y):# c ? x : y
        return self.raw('MUX', [c, x, y])
    def ULT(self, a, b):   return self.raw('ULT', [a, b])

def gen_net():
    net = Net()
    x = net.IN()
    # ---- integer sqrt: subtraction/bit method, 16 fixed steps ----
    res = net.CONST(0)
    rem = x
    bit = net.CONST(1 << 30)
    for _ in range(16):
        cand = net.ADD(res, bit)          # res + bit
        too_big = net.ULT(rem, cand)      # 1 when rem < res+bit
        diff = net.SUB(rem, cand)         # rem - (res+bit)
        new_rem = net.MUX(too_big, rem, diff)
        res_half = net.SHR(res, 1)
        res_plus = net.ADD(res_half, bit)
        new_res = net.MUX(too_big, res_half, res_plus)
        bit = net.SHR(bit, 2)
        rem, res = new_rem, new_res
    s = res
    # ---- Fibonacci fast doubling over the 32 bits of s ----
    a = net.CONST(0)
    b = net.CONST(1)
    one = net.CONST(1)
    for k in range(31, -1, -1):
        two_b = net.SHL(b, 1)
        neg = net.SUB(two_b, a)           # 2*b - a
        f2n   = net.MUL(a, neg)           # F(2n)
        a_sq  = net.MUL(a, a)
        b_sq  = net.MUL(b, b)
        f2n1  = net.ADD(a_sq, b_sq)       # F(2n+1)
        f2n2  = net.ADD(f2n, f2n1)        # F(2n+2)
        sb    = net.AND(net.SHR(s, k), one)  # bit k of s
        a = net.MUX(sb, f2n1, f2n)        # bit 1 -> F(2n+1), else F(2n)
        b = net.MUX(sb, f2n2, f2n1)
    net.out = a
    return net

net = gen_net()
CAP = 600
n = len(net.nodes)
assert n <= CAP, f"network too large: {n} > {CAP}"
lines = ["VERSION 1", "BITS 32", f"NODES {CAP}", f"OUTPUT {net.out}", ""]
for i, (op, args) in enumerate(net.nodes):
    lines.append(f"{i} = {op} " + " ".join(str(a) for a in args))
with open('/app/gate_net.txt', 'w') as f:
    f.write("\n".join(lines) + "\n")
print(f"[gate_net.txt] {n} node lines (cap {CAP})")
PY

cat > /app/gate_validate.py <<'PY'
"""Self-checking validator for /app/gate_net.txt against the isqrt+Fibonacci reference."""
import sys

MASK = 0xFFFFFFFF

def fib_mod(n):
    def fd(k):
        if k == 0:
            return (0, 1)
        a, b = fd(k >> 1)
        c = (a * ((2 * b - a) & MASK)) & MASK
        d = (a * a + b * b) & MASK
        if k & 1:
            return (d, (c + d) & MASK)
        return (c, d)
    return fd(max(n, 0))[0]

def reference(x):
    import math
    s = math.isqrt(x)
    return fib_mod(s)

def parse_net(path):
    nodes = []
    out = None
    for raw in open(path):
        line = raw.split('#', 1)[0].strip()
        if not line:
            continue
        head = line.split()
        if line[0].isdigit():
            nid, eq, op = head[0], head[1], head[2]
            nodes.append((op, [int(h) for h in head[3:]]))
        elif head[0] == 'OUTPUT':
            out = int(head[1])
    return nodes, out

def run_net(nodes, out, x):
    v = 0
    vals = [0] * len(nodes)
    for i, (op, args) in enumerate(nodes):
        if op == 'IN':
            vals[i] = x
        elif op == 'CONST':
            vals[i] = args[0]
        elif op == 'ADD':
            vals[i] = (vals[args[0]] + vals[args[1]]) & MASK
        elif op == 'SUB':
            vals[i] = (vals[args[0]] - vals[args[1]]) & MASK
        elif op == 'MUL':
            vals[i] = (vals[args[0]] * vals[args[1]]) & MASK
        elif op == 'SHL':
            vals[i] = (vals[args[0]] << args[1]) & MASK
        elif op == 'SHR':
            vals[i] = vals[args[0]] >> args[1]
        elif op == 'AND':
            vals[i] = vals[args[0]] & vals[args[1]]
        elif op == 'OR':
            vals[i] = vals[args[0]] | vals[args[1]]
        elif op == 'XOR':
            vals[i] = vals[args[0]] ^ vals[args[1]]
        elif op == 'NOT':
            vals[i] = (~vals[args[0]]) & MASK
        elif op == 'MUX':
            vals[i] = vals[args[1]] if vals[args[0]] else vals[args[2]]
        elif op == 'ULT':
            vals[i] = 1 if vals[args[0]] < vals[args[1]] else 0
    return vals[out if out is not None else len(nodes) - 1]

def load_inputs(path):
    vals = []
    for raw in open(path):
        line = raw.split('#', 1)[0].strip()
        if not line:
            continue
        vals.append(int(line, 0))
    return vals

def main():
    if len(sys.argv) < 2:
        print("usage: gate_validate.py <inputs_file>")
        return 2
    try:
        nodes, out = parse_net('/app/gate_net.txt')
        xvals = load_inputs(sys.argv[1])
        bad = 0
        for x in xvals:
            got = run_net(nodes, out, x & MASK)
            exp = reference(x & MASK)
            if got != exp:
                bad += 1
                if bad <= 5:
                    print(f"FAIL x={x} expected={exp} got={got}")
        if bad:
            print(f"FAIL ({bad} mismatches)")
            return 1
        print("PASS")
        return 0
    except Exception as e:  # noqa: BLE001
        print(f"FAIL internal error: {e!r}")
        return 1

if __name__ == '__main__':
    sys.exit(main())
PY

# oracle self-check on a broad vector set
python3 - <<'PY'
import random
random.seed(1234)
vals = [0, 1, 2, 3, 4, 8, 9, 15, 16, 255, 256, 65535, 65536,
        65535**2, 65536**2 - 1, 2**31, 2**32 - 1, 2**32 - 2]
vals += [random.randrange(2**32) for _ in range(3000)]
with open('/tmp/gate_selftest.txt', 'w') as f:
    for v in vals:
        f.write(hex(v) + "\n")
PY
python3 /app/gate_validate.py /tmp/gate_selftest.txt

# sanity: independent interpreter agrees on the same vectors (double-check)
python3 - <<'PY'
import importlib.util, math, random
spec = importlib.util.spec_from_file_location("gv", "/app/gate_validate.py")
gv = importlib.util.module_from_spec(spec); spec.loader.exec_module(gv)
nodes, out = gv.parse_net('/app/gate_net.txt')
vals = [int(l.strip(), 0) for l in open('/tmp/gate_selftest.txt') if l.strip() and not l.startswith('#')]
assert all(gv.run_net(nodes, out, v) == gv.reference(v) for v in vals)
print("[indep check] OK")
PY

# ---------------------------------------------------------------- Subtask 2
cat > /app/compress.py <<'PY'
"""Literal/back-reference compressor + decompressor (fixed token format).

Tokens: 0x00 <byte>            literal, 2 bytes
        0x01 <len16 LE><dist16 LE>  back-ref (dist>=1, len>=2, overlap allowed), 5 bytes
Segmentation chosen by dynamic programming over the longest-match table.
"""
import struct
import sys

MAXDIST = 65535
MAXLEN = 65535


def _matches(data):
    n = len(data)
    L = [0] * n
    D = [0] * n
    if n < 3:
        return L, D
    heads = {}
    for i in range(n - 2):
        key = data[i:i + 3]
        plist = heads.get(key)
        if plist:
            bestlen, bestdist = 0, 0
            for p in plist[-10:]:
                d = i - p
                if d < 1 or d > MAXDIST:
                    continue
                k = 0
                while k < MAXLEN and i + k < n and data[p + k] == data[i + k]:
                    k += 1
                if k > bestlen:
                    bestlen, bestdist = k, d
            L[i], D[i] = bestlen, bestdist
        lst = heads.setdefault(key, [])
        lst.append(i)
        # keep the window bounded
        if len(lst) > 64:
            heads[key] = lst[-32:]
    return L, D


def compress(data):
    n = len(data)
    L, D = _matches(data)
    INF = 1 << 60
    best = [INF] * (n + 1)
    best[n] = 0
    sel = [None] * (n + 1)
    for i in range(n - 1, -1, -1):
        best[i] = 2 + best[i + 1]
        sel[i] = ('L', 0, 0)
        ln = L[i]
        if ln >= 2 and i + ln <= n:
            c = 5 + best[i + ln]
            if c < best[i]:
                best[i] = c
                sel[i] = ('R', ln, D[i])
    out = bytearray()
    i = 0
    while i < n:
        kind, ln, dd = sel[i]
        if kind == 'L':
            out.append(0)
            out.append(data[i])
            i += 1
        else:
            out.append(1)
            out += struct.pack('<HH', ln, dd)
            i += ln
    return bytes(out)


def decompress(stream):
    out = bytearray()
    i = 0
    n = len(stream)
    while i < n:
        flag = stream[i]
        i += 1
        if flag == 0:
            out.append(stream[i])
            i += 1
        else:
            ln = struct.unpack_from('<H', stream, i)[0]
            dd = struct.unpack_from('<H', stream, i + 2)[0]
            i += 4
            if dd < 1 or dd > len(out):
                raise ValueError(f'back-reference beyond output (dist={dd})')
            start = len(out) - dd
            for _ in range(ln):
                out.append(out[start])
                start += 1
    return bytes(out)


def main():
    argv = sys.argv[1:]
    if argv and argv[0] == '--decompress':
        if len(argv) != 3:
            print('usage: compress.py --decompress <in> <out>')
            return 2
        stream = open(argv[1], 'rb').read()
        open(argv[2], 'wb').write(decompress(stream))
        return 0
    if len(argv) != 2:
        print('usage: compress.py <in> <out>')
        return 2
    data = open(argv[0], 'rb').read()
    open(argv[1], 'wb').write(compress(data))
    return 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
PY

# run the compressor on the provided corpus -> /app/payload.bin, then verify
python3 /app/compress.py /app/sample.dat /app/payload.bin
python3 /app/compress.py --decompress /app/payload.bin /tmp/payload_check.bin
SAMPLE_BYTES=$(stat -c%s /app/sample.dat)
PAY_BYTES=$(stat -c%s /app/payload.bin)
CK_BYTES=$(stat -c%s /tmp/payload_check.bin)
if ! cmp -s /app/sample.dat /tmp/payload_check.bin; then
    echo "ORACLE ERROR: payload round-trip mismatch" >&2; exit 1
fi
echo "[payload.bin] ${PAY_BYTES} bytes (budget < 2800), round-trip ${CK_BYTES}/${SAMPLE_BYTES} == original"

# ---------------------------------------------------------------- Subtask 3
BASELINE=$(cat /opt/site-baseline.txt)
MEASURED=$(python3 - <<'PY'
import os
import site
d = site.getsitepackages()[0]
n = 0
for r, _, fs in os.walk(d):
    for f in fs:
        try:
            n += os.path.getsize(os.path.join(r, f))
        except OSError:
            pass
print(n)
PY
)
LIMIT=$(( (BASELINE * 108 + 99) / 100 + 12 * 1024 * 1024 ))
cat > /app/footprint_report.txt <<EOF
baseline_bytes: ${BASELINE}
measured_bytes: ${MEASURED}
limit_bytes: ${LIMIT}
within_budget: $([ "$MEASURED" -le "$LIMIT" ] && echo true || echo false)
EOF
echo "[footprint_report.txt] baseline=${BASELINE} measured=${MEASURED} limit=${LIMIT}"

echo "== kite-summit oracle: done =="
ls -l /app
