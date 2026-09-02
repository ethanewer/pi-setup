#!/bin/bash
# Real oracle for glass-quill: synthesize the QFIB netlist, write the
# evaluator, and derive build_report.json from the shipped netlist. Never
# reads /tests.
set -eu

mkdir -p /app

# ---- 1. Synthesize the NLV2 netlist (this IS the work). --------------------
cat > /tmp/synth.py <<'PY'
M = 0xFFFFFFFF

nodes = []  # (op, args)

def emit(op, *args):
    nodes.append((op, args))
    return len(nodes) - 1

def K(v): return emit("K", v)
def ADD(a, b): return emit("ADD", a, b)
def SUB(a, b): return emit("SUB", a, b)
def MUL(a, b): return emit("MUL", a, b)
def SHL(a, k): return emit("SHL", a, k)
def SHR(a, k): return emit("SHR", a, k)
def AND(a, b): return emit("AND", a, b)
def OR(a, b): return emit("OR", a, b)
def XOR(a, b): return emit("XOR", a, b)
def NOT(a): return emit("NOT", a)
def CMP(a, b): return emit("CMP", a, b)
def SEL(c, a, b): return emit("SEL", c, a, b)

IN = emit("IN")

# --- isqrt(x) via digit recurrence: 16 fixed steps, bit = 2^30, 2^28, ... ---
rem = IN
res = K(0)
bit = K(1 << 30)
for _ in range(16):
    t = ADD(res, bit)              # candidate res + bit
    lt = CMP(rem, t)               # 1 when rem < t (skip branch)
    remsub = SUB(rem, t)
    rem = SEL(lt, rem, remsub)
    rh = SHR(res, 1)
    rhb = ADD(rh, bit)
    res = SEL(lt, rh, rhb)
    bit = SHR(bit, 2)

s = res

# --- F_s mod 2^32 via fast doubling over the 32 bits of s ------------------
a = K(0)    # F_0
b = K(1)    # F_1
for k in range(31, -1, -1):
    sb = AND(SHR(s, k), K(1))
    b2 = SHL(b, 1)
    t = SUB(b2, a)
    c = MUL(a, t)        # F_(2n)
    a2 = MUL(a, a)
    bb = MUL(b, b)
    d = ADD(a2, bb)      # F_(2n+1)
    e = ADD(c, d)        # F_(2n+2)
    a = SEL(sb, d, c)
    b = SEL(sb, e, d)

out = a
assert len(nodes) <= 768, len(nodes)

lines = ["NETLIST NLV2", "WIDTH 32", "BUDGET 768", "DRIVE %d" % out, ""]
for i, (op, args) in enumerate(nodes):
    lines.append("%d := %s %s" % (i, op, " ".join(str(v) for v in args)))
with open("/app/netlist.txt", "w") as fh:
    fh.write("\n".join(lines) + "\n")
print("synth: %d nodes" % len(nodes))
PY

python3 /tmp/synth.py
rm -f /tmp/synth.py

# ---- 2. The evaluator deliverable. ----------------------------------------
cat > /app/eval_net.py <<'PY'
#!/usr/bin/env python3
"""QFIB evaluator: runs an NLV2 netlist on a list of 32-bit inputs and
compares against an independent isqrt+fast-doubling-Fibonacci reference."""
import math
import re
import sys

MOD = 1 << 32

OPS = {"IN", "K", "ADD", "SUB", "MUL", "SHL", "SHR", "AND", "OR", "XOR",
       "NOT", "CMP", "SEL"}


def parse_netlist(path):
    drive = None
    entries = []
    seen_headers = True
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if not line[0].isdigit():
            if seen_headers is False:
                raise ValueError("header after node lines: %r" % line)
            tok = line.split(None, 1)
            if len(tok) != 2:
                raise ValueError("bad header %r" % line)
            key, val = tok[0], tok[1].strip()
            if key == "NETLIST":
                if val != "NLV2":
                    raise ValueError("bad format")
            elif key == "WIDTH":
                if int(val) != 32:
                    raise ValueError("bad width")
            elif key == "BUDGET":
                pass
            elif key == "DRIVE":
                drive = int(val)
            else:
                raise ValueError("unknown header %r" % line)
            continue
        seen_headers = False
        m = re.match(r"^(\d+)\s*:=\s*(\S+)(?:\s+(.*))?$", line)
        if not m:
            raise ValueError("bad node line %r" % line)
        nid, op, rest = int(m.group(1)), m.group(2), (m.group(3) or "").split()
        if op not in OPS:
            raise ValueError("unknown op %r" % op)
        expected = {"IN": 0, "K": 1, "NOT": 1, "SHL": 2, "SHR": 2, "SEL": 3}.get(op, 2)
        if len(rest) != expected:
            raise ValueError("op %s wants %d operands" % (op, expected))
        entries.append((nid, op, [int(v) for v in rest]))
    if drive is None:
        raise ValueError("missing DRIVE")
    return drive, entries


def evaluate_netlist(path, x):
    drive, entries = parse_netlist(path)
    nodes = {nid: (op, args) for nid, op, args in entries}
    memo = {}

    def go(i):
        if i in memo:
            return memo[i]
        op, args = nodes[i]
        if op == "IN":
            v = x & (MOD - 1)
        elif op == "K":
            v = args[0] & (MOD - 1)
        elif op == "ADD":
            v = (go(args[0]) + go(args[1])) & (MOD - 1)
        elif op == "SUB":
            v = (go(args[0]) - go(args[1])) & (MOD - 1)
        elif op == "MUL":
            v = (go(args[0]) * go(args[1])) & (MOD - 1)
        elif op == "SHL":
            v = (go(args[0]) << args[1]) & (MOD - 1)
        elif op == "SHR":
            v = go(args[0]) >> args[1]
        elif op == "AND":
            v = go(args[0]) & go(args[1])
        elif op == "OR":
            v = go(args[0]) | go(args[1])
        elif op == "XOR":
            v = go(args[0]) ^ go(args[1])
        elif op == "NOT":
            v = (~go(args[0])) & (MOD - 1)
        elif op == "CMP":
            v = 1 if go(args[0]) < go(args[1]) else 0
        elif op == "SEL":
            v = go(args[1]) if go(args[0]) != 0 else go(args[2])
        else:
            raise ValueError("bad op")
        memo[i] = v
        return v

    return go(drive)


def reference(x):
    s = math.isqrt(x)
    a, b = 0, 1  # F_0, F_1
    for c in bin(s)[2:]:
        a, b = (a * (2 * b - a)) % MOD, (a * a + b * b) % MOD
        if c == "1":
            a, b = b, (a + b) % MOD
    return s, a


def load_inputs(path):
    vals = []
    for raw in open(path, encoding="utf-8"):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        vals.append(int(line, 0))
    return vals


def main():
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print("usage: eval_net.py <inputs_file> [netlist_path]")
        return 2
    inputs_path = sys.argv[1]
    netlist = sys.argv[2] if len(sys.argv) == 3 else "/app/netlist.txt"
    ok = True
    for x in load_inputs(inputs_path):
        if not (0 <= x <= 0xFFFFFFFF):
            ok = False
            continue
        s, want = reference(x)
        try:
            got = evaluate_netlist(netlist, x)
        except Exception:
            got = None
        if got != want:
            ok = False
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x /app/eval_net.py

# ---- 3. build_report.json, derived from the shipped netlist. --------------
python3 - <<'PY'
import json
import math
import sys

sys.path.insert(0, "/app")
import importlib.util
spec = importlib.util.spec_from_file_location("ev", "/app/eval_net.py")
ev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ev)

drive, entries = ev.parse_netlist("/app/netlist.txt")
op_counts = {}
for _, op, _a in entries:
    op_counts[op] = op_counts.get(op, 0) + 1

probe = []
for line in open("/app/probe_inputs.txt"):
    line = line.split("#", 1)[0].strip()
    if not line:
        continue
    x = int(line, 0)
    s, y = ev.reference(x)
    probe.append({"x": str(x), "s": s, "y": y})

# self-check: the netlist must reproduce every probe value
for item in probe:
    got = ev.evaluate_netlist("/app/netlist.txt", int(item["x"]))
    assert got == item["y"], (item, got)

report = {
    "format": "NLV2",
    "width": 32,
    "budget": 768,
    "nodes_used": len(entries),
    "op_counts": op_counts,
    "probe": probe,
}
with open("/app/build_report.json", "w") as fh:
    json.dump(report, fh, indent=2)
print("report: nodes=%d ops=%s" % (len(entries), sorted(op_counts.items())))
PY

echo "solve.sh done"
ls -l /app/netlist.txt /app/eval_net.py /app/build_report.json
