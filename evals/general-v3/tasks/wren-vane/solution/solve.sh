#!/bin/bash
# Oracle for wren-vane: author the VECNET1 network for y = F(isqrt(x)) mod 2^32,
# author the vecsim.py evaluator, and run the simulator on the shipped probe
# vectors to produce /app/probe_out.json. Never reads /tests.
set -euo pipefail

NET="/app/vecnet.txt"
SIM="/app/vecsim.py"

# ---------------------------------------------------------------- 1. netlist
python3 - "$NET" <<'PY'
import sys

MASK = 0xFFFFFFFF

class Net:
    def __init__(self):
        self.lines = []
    def raw(self, text):
        self.lines.append(text)
        return len(self.lines) - 1
    def IN(self):            return self.raw("IN")
    def K(self, v):          return self.raw(f"K {int(v) & MASK}")
    def ADD(self, a, b):     return self.raw(f"ADD {a} {b}")
    def SUB(self, a, b):     return self.raw(f"SUB {a} {b}")
    def MUL(self, a, b):     return self.raw(f"MUL {a} {b}")
    def SLL(self, a, k):     return self.raw(f"SLL {a} {int(k)}")
    def SRL(self, a, k):     return self.raw(f"SRL {a} {int(k)}")
    def AND(self, a, b):     return self.raw(f"AND {a} {b}")
    def OR(self, a, b):      return self.raw(f"OR {a} {b}")
    def XOR(self, a, b):     return self.raw(f"XOR {a} {b}")
    def NOT(self, a):        return self.raw(f"NOT {a}")
    def SEL(self, c, x, y):  return self.raw(f"SEL {c} {x} {y}")
    def LTU(self, a, b):     return self.raw(f"LTU {a} {b}")

net = Net()
x = net.IN()

# ---- stage A: isqrt(x) via the 16-step restoring bit-by-bit method ----
res = net.K(0)          # running root
rem = x                 # remaining value
bit = net.K(1 << 30)    # 4^15
for _ in range(16):
    cand = net.ADD(res, bit)        # res + bit
    too_big = net.LTU(rem, cand)    # rem < res+bit ?
    diff = net.SUB(rem, cand)       # rem - (res+bit)
    rem = net.SEL(too_big, rem, diff)
    res_half = net.SRL(res, 1)
    res_plus = net.ADD(res_half, bit)
    res = net.SEL(too_big, res_half, res_plus)
    bit = net.SRL(bit, 2)
s = res

# ---- stage B: F_s mod 2^32 via 32 unconditional fast-doubling steps ----
a = net.K(0)            # F(k)
b = net.K(1)            # F(k+1)
one = net.K(1)
for i in range(31, -1, -1):
    two_b = net.SLL(b, 1)
    neg = net.SUB(two_b, a)          # 2*F(k+1) - F(k)   (mod 2^32)
    f2k = net.MUL(a, neg)            # F(2k)
    a_sq = net.MUL(a, a)
    b_sq = net.MUL(b, b)
    f2k1 = net.ADD(a_sq, b_sq)       # F(2k+1)
    f2k2 = net.ADD(f2k, f2k1)        # F(2k+2)
    sb = net.AND(net.SRL(s, i), one)
    a = net.SEL(sb, f2k1, f2k)
    b = net.SEL(sb, f2k2, f2k1)
out = a

n = len(net.lines)
CAP = 1200
assert n <= CAP, f"network too large: {n} > {CAP}"
with open(sys.argv[1], "w") as f:
    f.write("FORMAT VECNET1\n")
    f.write("WIDTH 32\n")
    f.write(f"NODES {n}\n")
    f.write(f"OUTPUT {out}\n")
    for i, t in enumerate(net.lines):
        f.write(f"{i} = {t}\n")
print(f"[vecnet.txt] wrote {n} nodes (cap {CAP}), output node {out}")
PY

# ---------------------------------------------------------------- 2. vecsim
cat > "$SIM" <<'PY'
#!/usr/bin/env python3
"""VECNET1 evaluator: python3 vecsim.py NETLIST VECFILE OUTJSON."""
import json
import sys

MASK = 0xFFFFFFFF
WIDTH = 32


def parse_int(tok):
    tok = tok.strip()
    if tok.lower().startswith("0x") or tok.lower().startswith("-0x"):
        return int(tok, 16)
    return int(tok, 10)


def load_netlist(path):
    n = None
    out_id = None
    nodes = []
    fmt_ok = False
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            head = parts[0]
            if head == "FORMAT":
                if parts[1] != "VECNET1":
                    raise ValueError("bad FORMAT")
                fmt_ok = True
                continue
            if head == "WIDTH":
                if int(parts[1]) != WIDTH:
                    raise ValueError("bad WIDTH")
                continue
            if head == "NODES":
                n = int(parts[1])
                continue
            if head == "OUTPUT":
                out_id = int(parts[1])
                continue
            # node definition: <id> = OP args...
            if len(parts) < 3 or parts[1] != "=":
                raise ValueError("bad node line: %r" % line)
            nid = int(head)
            op = parts[2]
            args = parts[3:]
            nodes.append((nid, op, args))
    if not fmt_ok or n is None or out_id is None:
        raise ValueError("missing header lines")
    if n != len(nodes):
        raise ValueError("NODES mismatch")
    return n, out_id, nodes


ARITY = {"IN": 0, "K": 1, "NOT": 1, "SLL": 2, "SRL": 2,
         "ADD": 2, "SUB": 2, "MUL": 2, "AND": 2, "OR": 2,
         "XOR": 2, "LTU": 2, "SEL": 3}


def eval_node(op, args, val, inp_value, in_seen):
    if op == "IN":
        if in_seen[0]:
            raise ValueError("multiple IN nodes")
        in_seen[0] = True
        return inp_value & MASK
    if op == "K":
        v = parse_int(args[0])
        if not (0 <= v <= MASK):
            raise ValueError("constant out of range")
        return v
    if op in ("ADD", "SUB", "MUL", "AND", "OR", "XOR"):
        a, b = val[int(args[0])], val[int(args[1])]
        if op == "ADD":
            return (a + b) & MASK
        if op == "SUB":
            return (a - b) & MASK
        if op == "MUL":
            return (a * b) & MASK
        if op == "AND":
            return a & b
        if op == "OR":
            return a | b
        return a ^ b
    if op in ("SLL", "SRL"):
        k = int(args[1])
        if not (0 <= k <= 31):
            raise ValueError("shift out of range")
        a = val[int(args[0])]
        if op == "SLL":
            return (a << k) & MASK
        return (a >> k) & MASK
    if op == "NOT":
        return (~val[int(args[0])]) & MASK
    if op == "SEL":
        c = val[int(args[0])]
        return val[int(args[1])] if c != 0 else val[int(args[2])]
    if op == "LTU":
        return 1 if val[int(args[0])] < val[int(args[1])] else 0
    raise ValueError("unknown op %r" % op)


def main():
    if len(sys.argv) != 4:
        print("usage: vecsim.py NETLIST VECFILE OUTJSON", file=sys.stderr)
        return 2
    net_path, vec_path, out_path = sys.argv[1:4]
    n, out_id, nodes = load_netlist(net_path)
    if not (0 <= out_id < n):
        raise ValueError("OUTPUT out of range")

    xs = []
    with open(vec_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            t = raw.split("#", 1)[0].strip()
            if t:
                v = parse_int(t)
                if not (0 <= v <= MASK):
                    raise ValueError("input out of range")
                xs.append(v)

    # structural checks: ids in order, arity ok, refs strictly earlier
    for pos, (nid, op, args) in enumerate(nodes):
        if nid != pos:
            raise ValueError("node ids must be 0..n-1 in order")
        if op not in ARITY or len(args) != ARITY[op]:
            raise ValueError("bad op/arity for %s" % op)
        if op == "K":
            continue
        for i, a in enumerate(args):
            ref = int(a)
            if ref >= nid:
                raise ValueError("operand not strictly earlier")
            if op in ("SLL", "SRL") and i == 1:
                continue  # immediate shift amount

    results = []
    for xv in xs:
        val = [0] * n
        in_seen = [False]
        for nid, op, args in nodes:
            val[nid] = eval_node(op, args, val, xv, in_seen)
        if not in_seen[0]:
            raise ValueError("no IN node")
        results.append(val[out_id])

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(results, fh)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$SIM"

# ------------------------------------------------- 3. visible probe outputs
python3 "$SIM" /app/vecnet.txt /app/probe_in.txt /app/probe_out.json
echo "[probe_out.json] written"

# self-check the oracle against an independent python reference
python3 - <<'PY'
import json, math, subprocess, sys
sys.path.insert(0, "/app")

def fib_mod(n):
    def fd(k):
        if k == 0:
            return (0, 1)
        a, b = fd(k >> 1)
        c = (a * ((2 * b - a) & 0xFFFFFFFF)) & 0xFFFFFFFF
        d = (a * a + b * b) & 0xFFFFFFFF
        return ((d, (c + d) & 0xFFFFFFFF) if k & 1 else (c, d))
    return fd(n)[0]

xs = []
for line in open("/app/probe_in.txt"):
    t = line.strip()
    if t:
        xs.append(int(t, 16) if t.lower().startswith("0x") else int(t))
want = [fib_mod(math.isqrt(x)) for x in xs]
got = json.load(open("/app/probe_out.json"))
assert got == want, (got[:5], want[:5])
print("[self-check] probe outputs match the reference:", len(xs), "vectors")
PY
echo "wren-vane oracle: done"
