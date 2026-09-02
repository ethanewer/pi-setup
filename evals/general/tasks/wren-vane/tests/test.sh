#!/bin/bash
# Verifier for wren-vane: parses /app/vecnet.txt with an INDEPENDENT VECNET1
# evaluator, enforces every documented format rule, checks the network's
# outputs against the exact reference F(isqrt(x)) mod 2^32 on the visible probe
# vectors and on every hidden vector file, runs the deliverable evaluator
# /app/vecsim.py on the same vectors, and checks /app/probe_out.json.
# Writes 1 or 0 to /logs/verifier/reward.txt. Never crashes on malformed
# agent output: every parse is guarded.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_PROBE_SHA="dab3dc2e8108c29fa3c75485b34b97b02f1f6249ff3b4cef5f31a1ce0822afb2"
export PRISTINE_PROBE_SHA

python3 - <<'PY'
import hashlib, json, math, os, subprocess, sys

MASK = 0xFFFFFFFF
NET = "/app/vecnet.txt"
SIM = "/app/vecsim.py"
fails = []

def sha(p):
    try:
        return hashlib.sha256(open(p, "rb").read()).hexdigest()
    except OSError:
        return None

# ---- no-modify guard on the shipped probe vectors -------------------------
pristine = os.environ.get("PRISTINE_PROBE_SHA", "")
if pristine and sha("/app/probe_in.txt") != pristine:
    fails.append("/app/probe_in.txt was modified or missing")

# ---- reference implementation --------------------------------------------
def fib_mod(n):
    def fd(k):
        if k == 0:
            return (0, 1)
        a, b = fd(k >> 1)
        c = (a * ((2 * b - a) & MASK)) & MASK
        d = (a * a + b * b) & MASK
        return ((d, (c + d) & MASK) if k & 1 else (c, d))
    return fd(n)[0]

def ref(x):
    return fib_mod(math.isqrt(x))

def parse_vec(path):
    xs = []
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            t = raw.split("#", 1)[0].strip()
            if not t:
                continue
            v = int(t, 16) if t.lower().startswith("0x") else int(t, 10)
            if not (0 <= v <= MASK):
                raise ValueError("input out of range: %s" % t)
            xs.append(v)
    return xs

ARITY = {"IN": 0, "K": 1, "NOT": 1, "SLL": 2, "SRL": 2, "ADD": 2, "SUB": 2,
         "MUL": 2, "AND": 2, "OR": 2, "XOR": 2, "LTU": 2, "SEL": 3}

def load_and_eval(net_path, xs):
    """Independent VECNET1 evaluator; raises on any format violation."""
    n = out_id = None
    fmt = width = None
    nodes = []
    with open(net_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            if parts[0] == "FORMAT":
                fmt = parts[1]
                continue
            if parts[0] == "WIDTH":
                width = int(parts[1])
                continue
            if parts[0] == "NODES":
                n = int(parts[1])
                continue
            if parts[0] == "OUTPUT":
                out_id = int(parts[1])
                continue
            if len(parts) < 3 or parts[1] != "=":
                raise ValueError("bad line: %r" % line)
            nodes.append((int(parts[0]), parts[2], parts[3:]))
    if fmt != "VECNET1" or width != 32:
        raise ValueError("bad FORMAT/WIDTH")
    if n is None or out_id is None:
        raise ValueError("missing NODES/OUTPUT")
    if n != len(nodes):
        raise ValueError("NODES mismatch: %d vs %d lines" % (n, len(nodes)))
    if n > 1200:
        raise ValueError("network too large: %d > 1200" % n)
    for pos, (nid, op, args) in enumerate(nodes):
        if nid != pos:
            raise ValueError("node ids must be 0..n-1 in increasing order")
        if op not in ARITY or len(args) != ARITY[op]:
            raise ValueError("bad op/arity %r" % op)
        if op == "K":
            v = int(args[0], 16) if args[0].lower().startswith("0x") else int(args[0])
            if not (0 <= v <= MASK):
                raise ValueError("constant out of range")
            continue
        for i, a in enumerate(args):
            if op in ("SLL", "SRL") and i == 1:
                k = int(a)
                if not (0 <= k <= 31):
                    raise ValueError("shift amount out of range")
                continue
            if int(a) >= nid:
                raise ValueError("operand %s not strictly earlier than %d" % (a, nid))

    outs = []
    for xv in xs:
        val = [0] * n
        seen_in = False
        for pos, (nid, op, args) in enumerate(nodes):
            if op == "IN":
                if seen_in:
                    raise ValueError("multiple IN nodes")
                seen_in = True
                val[nid] = xv & MASK
            elif op == "K":
                val[nid] = int(args[0], 16) if args[0].lower().startswith("0x") else int(args[0])
            elif op in ("ADD", "SUB", "MUL"):
                a, b = val[int(args[0])], val[int(args[1])]
                val[nid] = (a + b if op == "ADD" else a - b if op == "SUB" else a * b) & MASK
            elif op in ("AND", "OR", "XOR"):
                a, b = val[int(args[0])], val[int(args[1])]
                val[nid] = a & b if op == "AND" else a | b if op == "OR" else a ^ b
            elif op == "SLL":
                val[nid] = (val[int(args[0])] << int(args[1])) & MASK
            elif op == "SRL":
                val[nid] = (val[int(args[0])] >> int(args[1])) & MASK
            elif op == "NOT":
                val[nid] = (~val[int(args[0])]) & MASK
            elif op == "SEL":
                val[nid] = val[int(args[1])] if val[int(args[0])] != 0 else val[int(args[2])]
            elif op == "LTU":
                val[nid] = 1 if val[int(args[0])] < val[int(args[1])] else 0
        if not seen_in:
            raise ValueError("no IN node")
        if not (0 <= out_id < n):
            raise ValueError("OUTPUT out of range")
        outs.append(val[out_id])
    return outs

def run_vecsim(vec_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run([sys.executable, SIM, NET, vec_path, out_path],
                           capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return None, "vecsim timeout"
    if r.returncode != 0 or not os.path.exists(out_path):
        return None, "vecsim rc=%d %s" % (r.returncode, (r.stderr or "")[-200:])
    try:
        with open(out_path) as fh:
            got = json.load(fh)
    except Exception as e:
        return None, "vecsim output unparseable: %s" % e
    if not isinstance(got, list) or len(got) != len(parse_vec(vec_path)):
        return None, "vecsim output shape wrong"
    try:
        return [int(v) & MASK for v in got], None
    except Exception:
        return None, "vecsim output not integers"

def check_case(vec_path, exp_path, label):
    try:
        xs = parse_vec(vec_path)
        want = json.load(open(exp_path))
    except Exception as e:
        fails.append("%s: fixture unreadable (%s)" % (label, e))
        return
    want = [int(v) & MASK for v in want]
    # independent evaluator on the agent's network
    try:
        got_net = load_and_eval(NET, xs)
        if got_net != want:
            bad = [i for i in range(len(want)) if got_net[i] != want[i]][:5]
            fails.append("%s: netlist wrong at vectors %s" % (label, bad))
    except Exception as e:
        fails.append("%s: netlist rejected by format evaluator: %s" % (label, e))
    # deliverable evaluator
    got, err = run_vecsim(vec_path, "/tmp/wren_vane_out.json")
    if err:
        fails.append("%s: vecsim failed: %s" % (label, err))
    elif got != want:
        bad = [i for i in range(len(want)) if got[i] != want[i]][:5]
        fails.append("%s: vecsim mismatch at vectors %s" % (label, bad))

# ---- deliverables exist ----------------------------------------------------
for p in (NET, SIM, "/app/probe_out.json"):
    if not os.path.isfile(p):
        fails.append("missing deliverable %s" % p)

if not fails:
    # visible probe vectors via independent evaluator + vecsim
    check_case("/app/probe_in.txt", "/tests/expected_probe.json", "visible")

    # /app/probe_out.json deliverable
    try:
        got = json.load(open("/app/probe_out.json"))
        want = json.load(open("/tests/expected_probe.json"))
        if [int(v) & MASK for v in got] != [int(v) & MASK for v in want]:
            fails.append("probe_out.json does not match expected")
    except Exception as e:
        fails.append("probe_out.json unreadable: %s" % e)

    # hidden cases
    hdir = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hdir)
                   if os.path.isdir(os.path.join(hdir, d))) if os.path.isdir(hdir) else []
    if len(cases) < 2:
        fails.append("expected >=2 hidden cases, found %d" % len(cases))
    for c in cases:
        check_case(os.path.join(hdir, c, "vectors.txt"),
                   os.path.join(hdir, c, "expected.json"), "hidden/%s" % c)

print("verify failures:", fails)
sys.exit(1 if fails else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
