#!/bin/bash
# Oracle for quartz-rune: generate the gate network + validator + report.
# Works from a pristine container; never reads /tests.
set -eu

cat > /tmp/gen_circuit.py <<'PYEOF'
#!/usr/bin/env python3
"""Generate the gate circuit for y = F(isqrt(x)) mod 2^32 plus the validator."""
CIRCUIT = "/app/circuit.gn"
VALIDATOR = "/app/verify_circuit.py"
LIMIT = 520

OPS = {"IN","CONST","SUM","DIF","PRD","LSH","RSH","BAND","BOR","BXOR","FLIP","PICK","LESS"}


def gen_nodes():
    nodes = []
    consts = {}
    def emit(op, *args):
        nodes.append((op, [str(a) for a in args]))
        return len(nodes) - 1
    def const(v):
        if v not in consts:
            consts[v] = emit("CONST", v)
        return consts[v]

    xin = emit("IN")
    one = const(1)
    zero = const(0)
    bit0 = const(1 << 30)

    # ---- isqrt(x): 16 fixed restoring iterations ----
    rem = xin
    res = zero
    bit = bit0
    for _ in range(16):
        t = emit("SUM", res, bit)
        c = emit("LESS", rem, t)          # rem < t -> skip branch
        sub = emit("DIF", rem, t)
        rem = emit("PICK", c, rem, sub)
        resh = emit("RSH", res, 1)
        t2 = emit("SUM", resh, bit)
        res = emit("PICK", c, resh, t2)
        bit = emit("RSH", bit, 2)

    s = res

    # ---- F_s mod 2^32 by fast doubling over the 32 bits of s ----
    a = zero
    b = one
    for k in range(31, -1, -1):
        sb = emit("RSH", s, k)
        bitk = emit("BAND", sb, one)
        t1 = emit("LSH", b, 1)
        t2 = emit("DIF", t1, a)
        t3 = emit("PRD", a, t2)      # F_2n
        t4 = emit("PRD", a, a)
        t5 = emit("PRD", b, b)
        t6 = emit("SUM", t4, t5)     # F_2n+1
        t7 = emit("SUM", t3, t6)     # F_2n+2
        na = emit("PICK", bitk, t6, t3)
        nb = emit("PICK", bitk, t7, t6)
        a, b = na, nb

    assert len(nodes) <= LIMIT, len(nodes)
    return nodes, a


VALIDATOR_SRC = r'''#!/usr/bin/env python3
"""Validator for /app/circuit.gn.

Usage: python3 /app/verify_circuit.py <inputs_file>
Prints PASS and exits 0 iff the network reproduces the exact reference
y = F(isqrt(x)) mod 2^32 for every input in the file.
"""
import math
import sys

CIRCUIT = "/app/circuit.gn"
OPS = {"IN", "CONST", "SUM", "DIF", "PRD", "LSH", "RSH",
       "BAND", "BOR", "BXOR", "FLIP", "PICK", "LESS"}
M32 = 0xFFFFFFFF


def parse_circuit(path):
    headers = {}
    nodes = {}
    order = []
    in_nodes = False
    with open(path) as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            key = line.split(" ", 1)[0]
            if not in_nodes and key in ("VERSION", "WIDTH", "LIMIT", "RESULT") \
                    and "=" not in line:
                headers[key] = line.split(" ", 1)[1].strip()
                if key == "RESULT":
                    in_nodes = True
                continue
            if "=" not in line:
                raise ValueError("bad line: %r" % line)
            lhs, rhs = line.split("=", 1)
            nid = int(lhs.strip())
            parts = rhs.split()
            op = parts[0]
            if op not in OPS:
                raise ValueError("unknown op %r" % op)
            args = [int(p) for p in parts[1:]]
            if nid in nodes or nid != len(order):
                raise ValueError("bad node id %d" % nid)
            for a in args:
                if op not in ("CONST", "IN") and a >= nid:
                    raise ValueError("forward reference %d in node %d" % (a, nid))
            nodes[nid] = (op, args)
            order.append(nid)
    if "RESULT" not in headers:
        raise ValueError("missing RESULT")
    limit = int(headers.get("LIMIT", "0"))
    if limit and len(order) > limit:
        raise ValueError("node count %d exceeds LIMIT %d" % (len(order), limit))
    return nodes, int(headers["RESULT"]), limit


def evaluate(nodes, out_id, x):
    vals = {}
    for nid in sorted(nodes):
        op, args = nodes[nid]
        if op == "IN":
            v = x & M32
        elif op == "CONST":
            v = args[0] & M32
        elif op == "SUM":
            v = (vals[args[0]] + vals[args[1]]) & M32
        elif op == "DIF":
            v = (vals[args[0]] - vals[args[1]]) & M32
        elif op == "PRD":
            v = (vals[args[0]] * vals[args[1]]) & M32
        elif op == "LSH":
            v = (vals[args[0]] << args[1]) & M32
        elif op == "RSH":
            v = (vals[args[0]] >> args[1]) & M32
        elif op == "BAND":
            v = vals[args[0]] & vals[args[1]]
        elif op == "BOR":
            v = vals[args[0]] | vals[args[1]]
        elif op == "BXOR":
            v = vals[args[0]] ^ vals[args[1]]
        elif op == "FLIP":
            v = (~vals[args[0]]) & M32
        elif op == "PICK":
            v = vals[args[1]] if vals[args[0]] != 0 else vals[args[2]]
        elif op == "LESS":
            v = 1 if vals[args[0]] < vals[args[1]] else 0
        else:
            raise ValueError(op)
        vals[nid] = v
    return vals[out_id]


def fib_mod(n):
    """F_n mod 2^32 by fast doubling (iterative)."""
    a, b = 0, 1
    for bit in bin(n)[2:]:
        c = (a * ((2 * b - a) % (1 << 32))) % (1 << 32)
        d = (a * a + b * b) % (1 << 32)
        if bit == "1":
            a, b = d, (c + d) % (1 << 32)
        else:
            a, b = c, d
    return a


def reference(x):
    return fib_mod(math.isqrt(x))


def read_inputs(path):
    out = []
    with open(path) as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            out.append(int(line, 0))
    return out


def main():
    if len(sys.argv) != 2:
        print("usage: verify_circuit.py <inputs_file>")
        return 2
    nodes, out_id, _limit = parse_circuit(CIRCUIT)
    ok = True
    for x in read_inputs(sys.argv[1]):
        got = evaluate(nodes, out_id, x)
        want = reference(x)
        if got != want:
            print("FAIL x=%d got=%d want=%d" % (x, got, want))
            ok = False
    if ok:
        print("PASS")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
'''


def main():
    nodes, out = gen_nodes()
    lines = [
        "VERSION quartz-rune/gate-v2",
        "WIDTH 32",
        "LIMIT %d" % LIMIT,
        "RESULT %d" % out,
        "# y = F(isqrt(x)) mod 2^32",
    ]
    for i, (op, args) in enumerate(nodes):
        lines.append("%d = %s %s" % (i, op, " ".join(args)))
    with open(CIRCUIT, "w") as f:
        f.write("\n".join(lines) + "\n")
    with open(VALIDATOR, "w") as f:
        f.write(VALIDATOR_SRC)
    print("circuit nodes=%d result=%d" % (len(nodes), out))
    return len(nodes), out


if __name__ == "__main__":
    main()
PYEOF

python3 /tmp/gen_circuit.py
chmod +x /app/verify_circuit.py

# Produce the visible-case report by actually evaluating the network on the
# supplied probe inputs (via the validator's own evaluator).
cat > /tmp/gen_report.py <<'PYEOF'
import importlib.util, json
spec = importlib.util.spec_from_file_location("vc", "/app/verify_circuit.py")
vc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vc)
nodes, out_id, _ = vc.parse_circuit("/app/circuit.gn")
xs = vc.read_inputs("/app/probe_inputs.txt")
outputs = {}
for x in xs:
    outputs[str(x)] = vc.evaluate(nodes, out_id, x)
report = {
    "task": "quartz-rune",
    "nodes": len(nodes),
    "result_node": out_id,
    "outputs": outputs,
}
with open("/app/circuit_report.json", "w") as f:
    json.dump(report, f, indent=1, sort_keys=True)
print("report written:", len(outputs), "entries")
PYEOF
python3 /tmp/gen_report.py
rm -f /tmp/gen_circuit.py /tmp/gen_report.py

# Self-check: the validator must PASS on the probe inputs.
python3 /app/verify_circuit.py /app/probe_inputs.txt

echo "quartz-rune solve done"
ls -l /app/circuit.gn /app/verify_circuit.py /app/circuit_report.json
