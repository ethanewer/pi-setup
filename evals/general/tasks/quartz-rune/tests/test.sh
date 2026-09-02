#!/bin/bash
# Verifier for quartz-rune: checks the deliverables exist, enforces the
# no-modify rule on /app/probe_inputs.txt, EXECUTES /app/verify_circuit.py on
# the visible probe inputs and on every hidden input file, and independently
# re-evaluates /app/circuit.gn with its own interpreter against expected.json.
# Writes 1.0 or 0.0 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0.0

PRISTINE_PROBE_SHA="bbf68dc9dc82b1c502d201a3ddfc7bc5f516340f0348a06522d8342a762e1f32"

probe_ok=0
if [ -f /app/probe_inputs.txt ]; then
    actual="$(sha256sum /app/probe_inputs.txt | awk '{print $1}')"
    if [ "$actual" = "$PRISTINE_PROBE_SHA" ]; then
        probe_ok=1
    else
        echo "no-modify: /app/probe_inputs.txt was modified" >&2
    fi
else
    echo "no-modify: /app/probe_inputs.txt missing" >&2
fi

python3 - "$probe_ok" <<'PY'
import json, os, subprocess, sys

M32 = 0xFFFFFFFF
probe_ok = int(sys.argv[1])
failures = []

if not probe_ok:
    failures.append("probe_inputs.txt modified or missing (no-modify rule)")

# ---------- independent network parser/evaluator (written separately) ----------
def load_net(path):
    """Returns (nodes dict, out_id, limit). Raises on any structural violation."""
    hdr = {}
    body = []
    stage = "header"
    for raw in open(path):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if stage == "header":
            tok = line.split()
            if tok[0] in ("VERSION", "WIDTH", "LIMIT", "RESULT") and "=" not in line:
                hdr[tok[0]] = tok[1] if len(tok) > 1 else ""
                if tok[0] == "RESULT":
                    stage = "body"
                continue
        if "=" not in line:
            raise ValueError("bad line %r" % line)
        left, right = [p.strip() for p in line.split("=", 1)]
        i = int(left)
        w = right.split()
        if not w:
            raise ValueError("empty rhs")
        op = w[0]
        if op not in ("IN", "CONST", "SUM", "DIF", "PRD", "LSH", "RSH",
                      "BAND", "BOR", "BXOR", "FLIP", "PICK", "LESS"):
            raise ValueError("bad op %r" % op)
        body.append((i, op, [int(t) for t in w[1:]]))
    for k in ("VERSION", "WIDTH", "LIMIT", "RESULT"):
        if k not in hdr:
            raise ValueError("missing header %s" % k)
    if int(hdr["WIDTH"]) != 32:
        raise ValueError("WIDTH must be 32")
    prev = -1
    nodes = {}
    for i, op, args in body:
        if i != prev + 1:
            raise ValueError("node ids must be 0,1,2,... strictly increasing")
        prev = i
        if op == "IN":
            if args:
                raise ValueError("IN takes no args")
        elif op == "CONST":
            if len(args) != 1 or not (0 <= args[0] <= M32):
                raise ValueError("bad CONST")
        elif op in ("LSH", "RSH"):
            if len(args) != 2 or not (0 <= args[1] <= 31):
                raise ValueError("bad shift")
            if args[0] >= i:
                raise ValueError("forward ref")
        elif op == "FLIP":
            if len(args) != 1 or args[0] >= i:
                raise ValueError("bad FLIP")
        elif op in ("PICK",):
            if len(args) != 3 or any(a >= i for a in args):
                raise ValueError("bad PICK")
        elif op in ("SUM", "DIF", "PRD", "BAND", "BOR", "BXOR", "LESS"):
            if len(args) != 2 or any(a >= i for a in args):
                raise ValueError("bad binary op")
        else:
            raise ValueError("unreachable")
        nodes[i] = (op, args)
    out_id = int(hdr["RESULT"])
    if out_id not in nodes:
        raise ValueError("RESULT not a defined node")
    limit = int(hdr["LIMIT"])
    if len(body) > limit:
        raise ValueError("node count %d > LIMIT %d" % (len(body), limit))
    return nodes, out_id, limit


def run_net(nodes, out_id, x):
    st = {}
    for i in sorted(nodes):
        op, a = nodes[i]
        if op == "IN":
            v = x
        elif op == "CONST":
            v = a[0]
        elif op == "SUM":
            v = (st[a[0]] + st[a[1]]) & M32
        elif op == "DIF":
            v = (st[a[0]] - st[a[1]]) & M32
        elif op == "PRD":
            v = (st[a[0]] * st[a[1]]) & M32
        elif op == "LSH":
            v = (st[a[0]] << a[1]) & M32
        elif op == "RSH":
            v = (st[a[0]] >> a[1]) & M32
        elif op == "BAND":
            v = st[a[0]] & st[a[1]]
        elif op == "BOR":
            v = st[a[0]] | st[a[1]]
        elif op == "BXOR":
            v = st[a[0]] ^ st[a[1]]
        elif op == "FLIP":
            v = (~st[a[0]]) & M32
        elif op == "PICK":
            v = st[a[1]] if st[a[0]] else st[a[2]]
        elif op == "LESS":
            v = 1 if st[a[0]] < st[a[1]] else 0
        st[i] = v & M32
    return st[out_id]


def read_inputs(path):
    xs = []
    for raw in open(path):
        line = raw.split("#", 1)[0].strip()
        if line:
            xs.append(int(line, 0))
    return xs


def run_validator(inputs_file):
    """Executes the agent validator; True iff exit 0 and PASS on stdout."""
    try:
        r = subprocess.run([sys.executable, "/app/verify_circuit.py", inputs_file],
                           capture_output=True, text=True, timeout=120)
        return r.returncode == 0 and "PASS" in r.stdout
    except Exception:
        return False


def check_case(inputs_file, expected_file):
    try:
        want = json.load(open(expected_file))
        xs = read_inputs(inputs_file)
    except Exception:
        return "unreadable case files"
    try:
        nodes, out_id, _ = load_net("/app/circuit.gn")
    except Exception as e:
        return "circuit.gn invalid: %s" % e
    for x in xs:
        try:
            got = run_net(nodes, out_id, x)
        except Exception as e:
            return "eval error at x=%d: %s" % (x, e)
        if got != int(want[str(x)]):
            return "wrong output at x=%d: got %d want %d" % (x, got, int(want[str(x)]))
    if not run_validator(inputs_file):
        return "verify_circuit.py did not PASS on %s" % inputs_file
    return None


# ---------- 1. circuit.gn structure + validator on visible probe inputs ----------
if not os.path.isfile("/app/circuit.gn"):
    failures.append("missing /app/circuit.gn")
if not os.path.isfile("/app/verify_circuit.py"):
    failures.append("missing /app/verify_circuit.py")

if os.path.isfile("/app/probe_inputs.txt") and os.path.isfile("/tests/expected.json"):
    err = check_case("/app/probe_inputs.txt", "/tests/expected.json")
    if err:
        failures.append("visible case: " + err)

# ---------- 2. circuit_report.json must match the visible expected ----------
if not os.path.isfile("/app/circuit_report.json"):
    failures.append("missing /app/circuit_report.json")
else:
    try:
        rep = json.load(open("/app/circuit_report.json"))
        assert isinstance(rep, dict)
        assert set(rep.keys()) == {"task", "nodes", "result_node", "outputs"}, rep.keys()
        assert rep["task"] == "quartz-rune"
        assert isinstance(rep["nodes"], int) and isinstance(rep["result_node"], int)
        want = json.load(open("/tests/expected.json"))
        outs = rep["outputs"]
        assert isinstance(outs, dict)
        assert set(outs.keys()) == set(want.keys()), "report keys mismatch"
        for k, v in want.items():
            if int(outs[k]) != int(v):
                failures.append("circuit_report wrong at x=%s" % k)
                break
    except Exception as e:
        failures.append("circuit_report.json invalid: %s" % e)

# ---------- 3. hidden cases ----------
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d)))
    if len(cases) < 2:
        failures.append("expected >= 2 hidden cases")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        inp = os.path.join(base, "inputs.txt")
        exp = os.path.join(base, "expected.json")
        if not (os.path.isfile(inp) and os.path.isfile(exp)):
            failures.append("hidden '%s' malformed" % c)
            continue
        err = check_case(inp, exp)
        if err:
            failures.append("hidden '%s': %s" % (c, err))
else:
    failures.append("no hidden cases")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1.0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
