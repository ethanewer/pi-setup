#!/bin/bash
# Verifier for glass-quill: interprets the shipped /app/netlist.txt with an
# independent evaluator over the probe file and every hidden vector file,
# runs the agent's /app/eval_net.py on the same inputs, and cross-checks
# /app/build_report.json against the real netlist. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier
: > /logs/verifier/reward.txt

python3 - <<'PY'
import json
import math
import os
import re
import subprocess
import sys

MOD = 1 << 32
fails = []

# ---------- independent reference ----------
def reference(x):
    s = math.isqrt(x)
    a, b = 0, 1  # F_0, F_1
    for c in bin(s)[2:]:
        a, b = (a * (2 * b - a)) % MOD, (a * a + b * b) % MOD
        if c == "1":
            a, b = b, (a + b) % MOD
    return s, a

# ---------- independent NLV2 interpreter ----------
OPS = {"IN": 0, "K": 1, "ADD": 2, "SUB": 2, "MUL": 2, "SHL": 2, "SHR": 2,
       "AND": 2, "OR": 2, "XOR": 2, "NOT": 1, "CMP": 2, "SEL": 3}

def parse_netlist(path):
    headers = {}
    entries = []
    header_phase = True
    nlines = 0
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if not line[0].isdigit():
            if not header_phase:
                raise ValueError("header after node lines")
            parts = line.split(None, 1)
            if len(parts) != 2:
                raise ValueError("bad header %r" % line)
            headers[parts[0]] = parts[1].strip()
            continue
        header_phase = False
        m = re.match(r"^(\d+)\s*:=\s*(\S+)(?:\s+(.*))?$", line)
        if not m:
            raise ValueError("bad node line %r" % line)
        nid = int(m.group(1))
        op = m.group(2)
        args = [int(v) for v in (m.group(3) or "").split()]
        if op not in OPS:
            raise ValueError("unknown op %r" % op)
        if len(args) != OPS[op]:
            raise ValueError("arity for %s" % op)
        entries.append((nid, op, args))
        nlines += 1
    if "DRIVE" not in headers:
        raise ValueError("missing DRIVE")
    if entries and [e[0] for e in entries] != list(range(len(entries))):
        raise ValueError("ids not strictly increasing from 0")
    in_count = sum(1 for _, op, _a in entries if op == "IN")
    if in_count != 1:
        raise ValueError("expected exactly one IN, got %d" % in_count)
    budget = int(headers.get("BUDGET", "0"))
    if nlines > budget:
        raise ValueError("node lines %d exceed BUDGET %d" % (nlines, budget))
    return headers, entries, nlines

def make_interpreter(entries, drive):
    nodes = {nid: (op, args) for nid, op, args in entries}
    if drive not in nodes:
        raise ValueError("DRIVE %d not a node" % drive)

    def evaluate(x):
        x &= MOD - 1
        memo = {}

        def go(i):
            if i in memo:
                return memo[i]
            op, args = nodes[i]
            if op == "IN":
                v = x
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
    return evaluate

def load_inputs(path):
    vals = []
    for raw in open(path, encoding="utf-8"):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        vals.append(int(line, 0))
    return vals

# ---------- gate 1: the netlist itself ----------
netlist_path = "/app/netlist.txt"
evaluate = None
headers = {}
nlines = 0
op_counts = {}
if not os.path.isfile(netlist_path):
    fails.append("missing /app/netlist.txt")
else:
    try:
        headers, entries, nlines = parse_netlist(netlist_path)
        evaluate = make_interpreter(entries, int(headers["DRIVE"]))
        for _, op, _a in entries:
            op_counts[op] = op_counts.get(op, 0) + 1
        if headers.get("NETLIST") != "NLV2":
            fails.append("netlist format header wrong: %r" % headers.get("NETLIST"))
    except Exception as exc:
        fails.append("netlist unparseable: %s" % exc)

def check_vector_set(path, label):
    try:
        vals = load_inputs(path)
    except Exception as exc:
        fails.append("%s: unreadable inputs %s" % (label, exc))
        return
    if not vals:
        fails.append("%s: empty input set" % label)
        return
    for x in vals:
        if not (0 <= x <= 0xFFFFFFFF):
            fails.append("%s: out-of-domain input %d" % (label, x))
            continue
        s, want = reference(x)
        got = None
        if evaluate is not None:
            try:
                got = evaluate(x)
            except Exception:
                got = None
        if got != want:
            fails.append("%s: x=%d want=%d got=%r" % (label, x, want, got))

probe_inputs = "/app/probe_inputs.txt"
if os.path.isfile(probe_inputs):
    check_vector_set(probe_inputs, "probe")
else:
    fails.append("missing /app/probe_inputs.txt (environment tampered?)")

hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(
        os.path.join(hidden_dir, d) for d in os.listdir(hidden_dir)
        if os.path.isdir(os.path.join(hidden_dir, d)))
    if not cases:
        fails.append("no hidden cases present")
    for cdir in cases:
        inp = os.path.join(cdir, "inputs.txt")
        if not os.path.isfile(inp):
            fails.append("hidden %s malformed" % cdir)
            continue
        check_vector_set(inp, "hidden:%s" % os.path.basename(cdir))
else:
    fails.append("no hidden cases dir")

# ---------- gate 2: run the agent's evaluator deliverable ----------
if os.path.isfile("/app/eval_net.py"):
    eval_sets = []
    if os.path.isfile(probe_inputs):
        eval_sets.append(("probe", probe_inputs))
    if os.path.isdir(hidden_dir):
        for c in sorted(os.listdir(hidden_dir)):
            cdir = os.path.join(hidden_dir, c)
            inp = os.path.join(cdir, "inputs.txt")
            if os.path.isdir(cdir) and os.path.isfile(inp):
                eval_sets.append(("hidden:%s" % c, inp))
    for label, path in eval_sets:
        try:
            r = subprocess.run([sys.executable, "/app/eval_net.py", path],
                               capture_output=True, text=True, timeout=240)
        except Exception as exc:
            fails.append("%s: eval_net.py crashed: %s" % (label, exc))
            continue
        if r.returncode != 0 or "PASS" not in (r.stdout or ""):
            fails.append("%s: eval_net.py not PASS (rc=%s)" % (label, r.returncode))
else:
    fails.append("missing /app/eval_net.py")

# ---------- gate 3: build_report.json consistency ----------
if os.path.isfile("/app/build_report.json"):
    try:
        rep = json.load(open("/app/build_report.json"))
    except Exception as exc:
        rep = None
        fails.append("build_report.json unreadable: %s" % exc)
    if isinstance(rep, dict):
        if rep.get("format") != "NLV2" or rep.get("width") != 32:
            fails.append("build_report format/width wrong")
        if not isinstance(rep.get("budget"), int) or rep["budget"] < nlines:
            fails.append("build_report budget inconsistent with netlist")
        if rep.get("nodes_used") != nlines:
            fails.append("nodes_used %r != actual %d" % (rep.get("nodes_used"), nlines))
        rc = rep.get("op_counts")
        if not isinstance(rc, dict):
            fails.append("op_counts missing/not object")
        else:
            norm = {k: int(v) for k, v in rc.items() if v}
            want = {k: v for k, v in op_counts.items() if v}
            if norm != want:
                fails.append("op_counts mismatch: %r vs %r" % (norm, want))
        probe = rep.get("probe")
        if not isinstance(probe, list):
            fails.append("probe missing/not list")
        else:
            try:
                pvals = load_inputs(probe_inputs)
            except Exception:
                pvals = []
            if len(probe) != len(pvals):
                fails.append("probe length %d != %d" % (len(probe), len(pvals)))
            else:
                for item, x in zip(probe, pvals):
                    if not isinstance(item, dict):
                        fails.append("probe entry not object")
                        break
                    try:
                        ix = int(str(item.get("x")), 0)
                    except Exception:
                        fails.append("probe entry x unreadable")
                        break
                    if ix != x:
                        fails.append("probe x mismatch %r vs %d" % (item.get("x"), x))
                        break
                    s, y = reference(x)
                    if item.get("s") != s or item.get("y") != y:
                        fails.append("probe s/y wrong for x=%d" % x)
                        break
    elif rep is None:
        pass
else:
    fails.append("missing /app/build_report.json")

print("verify failures:", fails if fails else "none")
sys.exit(1 if fails else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then echo 1 > /logs/verifier/reward.txt; else echo 0 > /logs/verifier/reward.txt; fi
exit 0
