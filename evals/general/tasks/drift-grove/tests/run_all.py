#!/usr/bin/env python3
"""drift-grove verifier runner.

Executes every deliverable in /app, re-runs the shipped tools against hidden
scenarios in /tests/hidden, enforces every hard bound, and prints REWARD=0|1.
"""
import ast
import collections
import gzip
import json
import os
import random
import subprocess
import sys
from collections import deque
from fractions import Fraction

APP = "/app"
HID = "/tests/hidden"
FAILURES = []


def bad(name, detail=""):
    FAILURES.append(name)
    print("FAIL  %-28s %s" % (name, detail))


def ok(name):
    print("ok    %-28s" % name)


def sh(cmd, cwd=APP):
    return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)


# --------------------------------------------------------------------------
# Part 1 - sliding-tile BFS by depth
# --------------------------------------------------------------------------
def neighbors(state):
    empty = state.index(0)
    r, c = divmod(empty, 3)
    out = []
    for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nr, nc = r + dr, c + dc
        if 0 <= nr < 3 and 0 <= nc < 3:
            other = nr * 3 + nc
            cell = list(state)
            cell[empty], cell[other] = cell[other], cell[empty]
            out.append(tuple(cell))
    return out


def independent_bfs(board, goal):
    start, g = tuple(board), tuple(goal)
    dist = {start: 0}
    q = deque([start])
    while q:
        s = q.popleft()
        for nb in neighbors(s):
            if nb not in dist:
                dist[nb] = dist[s] + 1
                q.append(nb)
    layers = [[] for _ in range(max(dist.values()) + 1)]
    for s, d in dist.items():
        layers[d].append(s)
    return dist, layers


def validate_tile_report(name, rep, board, goal):
    dist, layers = independent_bfs(board, goal)
    if len(rep["layers"]) != len(layers):
        bad("tile.%s" % name, "layer count %d != %d" % (len(rep["layers"]), len(layers)))
        return
    for i, (a, b) in enumerate(zip(rep["layers"], layers)):
        if set(map(tuple, a)) != set(map(tuple, b)):
            bad("tile.%s" % name, "layer %d differs from recomputation" % i)
            return
    seen = set()
    for L in rep["layers"]:
        for s in L:
            if tuple(s) in seen:
                bad("tile.%s" % name, "state repeated across depths (not disjoint)")
                return
            seen.add(tuple(s))
    if len(seen) != rep["card"] or len(seen) != len(dist):
        bad("tile.%s" % name, "cardinality mismatch")
        return
    ch = [tuple(s) for s in rep["chain"]]
    if not ch or ch[0] != tuple(board):
        bad("tile.%s" % name, "chain does not start at board")
        return
    if tuple(goal) in dist:
        if ch[-1] != tuple(goal):
            bad("tile.%s" % name, "chain does not reach goal")
            return
        if len(ch) - 1 != dist[tuple(goal)]:
            bad("tile.%s" % name, "chain length %d != BFS distance %d" % (len(ch) - 1, dist[tuple(goal)]))
            return
        for a, b in zip(ch, ch[1:]):
            if b not in neighbors(a):
                bad("tile.%s" % name, "chain step %s -> %s not a single slide" % (a, b))
                return
    ok("tile.%s" % name)


def check_tile(name, board, goal):
    out = "/tmp/tile-%s.json" % name
    if not os.path.exists("/app/search.py"):
        bad("tile.%s" % name, "search.py missing")
        return
    r = sh(["python3", "/app/search.py", "/tmp/tile-in.json", out],
           cwd=os.path.dirname("/tmp/x"))
    if r.returncode != 0:
        bad("tile.%s" % name, "search.py crashed: %s" % r.stderr[-400:])
        return
    try:
        rep = json.load(open(out))
    except Exception as e:
        bad("tile.%s" % name, "unparseable output: %r" % e)
        return
    validate_tile_report(name, rep, board, goal)


def check_tile_artifact(name, board, goal):
    path = "/app/tile-solution.json"
    if not os.path.exists(path):
        bad("tile.%s" % name, "/app/tile-solution.json missing")
        return
    try:
        rep = json.load(open(path))
    except Exception as e:
        bad("tile.%s" % name, "unparseable /app/tile-solution.json: %r" % e)
        return
    for key in ("solved", "start", "goal", "card", "depth", "layers", "chain", "frontier_disjoint"):
        if key not in rep:
            bad("tile.%s" % name, "report missing schema key %r" % key)
            return
    if rep.get("start") != list(board) or rep.get("goal") != list(goal):
        bad("tile.%s" % name, "start/goal in artifact differ from fixture")
        return
    dist, _ = independent_bfs(board, goal)
    if rep.get("solved") != (tuple(goal) in dist):
        bad("tile.%s" % name, "solved flag does not match reachability")
        return
    validate_tile_report(name, rep, board, goal)


# --------------------------------------------------------------------------
# Part 2 - exact-target expression
# --------------------------------------------------------------------------
def rval(node):
    if isinstance(node, ast.Constant):
        return Fraction(node.value)
    if isinstance(node, ast.BinOp):
        a, b = rval(node.left), rval(node.right)
        op = node.op
        if isinstance(op, ast.Add):
            return a + b
        if isinstance(op, ast.Sub):
            return a - b
        if isinstance(op, ast.Mult):
            return a * b
        if isinstance(op, ast.Div):
            if b == 0:
                raise ValueError("division by zero")
            return a / b
        raise ValueError("unsupported operator")
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        return -rval(node.operand)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.UAdd):
        return rval(node.operand)
    raise ValueError("unsupported syntax")


def check_expr(name, nums, target, expr_text=None, from_file=False):
    if from_file:
        path = "/app/expr.txt"
        if not os.path.exists(path):
            bad("expr.%s" % name, "expr.txt missing")
            return
        text = open(path).read().strip()
    else:
        if not os.path.exists("/app/expr.py"):
            bad("expr.%s" % name, "expr.py missing")
            return
        r = sh(["python3", "/app/expr.py", "/tmp/expr-spec.json"])
        if r.returncode != 0:
            bad("expr.%s" % name, "expr.py failed: %s" % r.stderr[-300:])
            return
        text = r.stdout.strip()
    try:
        tree = ast.parse(text, mode="eval")
        value = rval(tree.body)
    except Exception as e:
        bad("expr.%s" % name, "cannot evaluate %r: %s" % (text[:60], e))
        return
    consts = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, int)]
    if collections.Counter(consts) != collections.Counter(nums):
        bad("expr.%s" % name, "numbers used != spec set: %s" % (consts,))
        return
    if value != Fraction(target):
        bad("expr.%s" % name, "evaluates to %s, expected %s" % (value, target))
        return
    ok("expr.%s" % name)


# --------------------------------------------------------------------------
# Part 3 - oracle binary search
# --------------------------------------------------------------------------
def oracle_len(seed):
    return (seed * 73 + 41) % 2001


def check_oracle(name, ctx_path, want):
    if not os.path.exists("/app/oracle-debug.py"):
        bad("oracle.%s" % name, "oracle-debug.py missing")
        return
    r = sh(["python3", "/app/oracle-debug.py", ctx_path])
    if r.returncode != 0:
        bad("oracle.%s" % name, "oracle-debug.py failed: %s" % r.stderr[-300:])
        return
    try:
        got = int(open("/app/lines.txt").read().strip())
        log = json.load(open("/app/probe-log.json"))
    except Exception as e:
        bad("oracle.%s" % name, "unreadable outputs: %r" % e)
        return
    if got != want:
        bad("oracle.%s" % name, "detected %d, expected %d" % (got, want))
        return
    if log.get("answer") != want:
        bad("oracle.%s" % name, "probe-log answer mismatch")
        return
    if log.get("calls", 0) > log.get("budget", 40):
        bad("oracle.%s" % name, "call budget exceeded: %s" % log.get("calls"))
        return
    eps = set(p.get("endpoint") for p in log.get("probes", []))
    if "span" not in eps or "leaf" not in eps:
        bad("oracle.%s" % name, "must use both control endpoints: %s" % sorted(eps))
        return
    # replay every logged probe against ground truth - a fabricated transcript fails
    for p in log.get("probes", []):
        k = int(p.get("k"))
        if p.get("endpoint") == "span":
            expect = "1" if 0 <= k < want else "0"
        else:
            expect = "leaf-%06d/%04d" % (k, want) if 0 <= k < want else "-EOF"
        if str(p.get("reply")) != expect:
            bad("oracle.%s" % name, "replayed probe %s k=%s replies %r != %r" % (p.get("endpoint"), k, p.get("reply"), expect))
            return
    ok("oracle.%s" % name)


# --------------------------------------------------------------------------
# Part 4 - gate netlist under the line cap
# --------------------------------------------------------------------------
def gen_bits(n, seed):
    r = random.Random(seed)
    return "".join(str(r.randint(0, 1)) for _ in range(n))


def check_gate_def(path, nbits, bitseed):
    if not os.path.exists(path):
        return "gate.def missing"
    lines = [ln for ln in open(path) if ln.strip()]
    if lines[0].startswith("INPUTS"):
        declared = int(lines[0].split()[1])
        n = declared
    else:
        return "bad header"
    if n != nbits:
        return "input width %d != %d" % (n, nbits)
    if len(lines) > 32000:
        return "line count %d exceeds cap 32000" % len(lines)
    bits = gen_bits(nbits, bitseed)
    open("/tmp/bits.txt", "w").write(bits)
    r = sh(["python3", APP + "/bin/sim-gates", path, "/tmp/bits.txt"])
    if r.returncode != 0:
        return "simulator rejected: %s" % r.stdout.strip()[:200]
    want = bits.count("1") % 2
    if "RESULT=%d" % want not in r.stdout:
        return "simulator result %r != expected parity" % r.stdout.strip()
    return None


def check_gate_gen(nbits, should_ok):
    if not os.path.exists("/app/gen-gate.py"):
        return "gen-gate.py missing"
    out = "/tmp/regen-ok.def" if should_ok else "/tmp/regen-refuse.def"
    r = sh(["python3", "/app/gen-gate.py", str(nbits), out, "32000"])
    if should_ok:
        if r.returncode != 0:
            return "gen-gate.py refused a feasible %d-input net: %s" % (nbits, r.stdout.strip())
        lines = [ln for ln in open(out) if ln.strip()]
        if len(lines) > 32000:
            return "regen net %d lines exceeds cap" % len(lines)
        return check_gate_def(out, nbits, 99)
    else:
        if r.returncode == 0:
            return "gen-gate.py accepted an impossible %d-input net" % nbits
        if "OVER_BUDGET" not in r.stdout:
            return "gen-gate.py failed for the wrong reason, not an over-budget refusal"
        if os.path.exists(out):
            return "gen-gate.py wrote an over-cap file instead of refusing"
        return None


# --------------------------------------------------------------------------
# Part 5 - substitution table under caps
# --------------------------------------------------------------------------
def check_table_file(path, bits, a, b, rows_cap=None, bytes_cap=None):
    rows = [ln for ln in open(path) if ln.strip()]
    mod = 1 << bits
    if rows_cap is not None and len(rows) > rows_cap:
        return "row count %d > cap %d" % (len(rows), rows_cap)
    if bytes_cap is not None and os.path.getsize(path) > bytes_cap:
        return "byte size %d > cap %d" % (os.path.getsize(path), bytes_cap)
    srcs = []
    dsts = []
    for ln in rows:
        try:
            s, d = ln.split(",")
            s, d = int(s.strip(), 16), int(d.strip(), 16)
        except Exception:
            return "unparseable row %r" % ln
        srcs.append(s)
        dsts.append(d)
    if sorted(srcs) != list(range(mod)):
        return "incomplete: %d/%d sources present" % (len(set(srcs)), mod)
    if len(set(dsts)) != mod:
        return "duplicate outputs (%d distinct)" % len(set(dsts))
    for s in srcs:
        if (a * s + b) % mod != dsts[srcs.index(s)]:
            return "wrong mapping at src %02X" % s
    return None


# --------------------------------------------------------------------------
# Part 6 - compressed tiny source
# --------------------------------------------------------------------------
def tiny_expected():
    S = " .:-=+*#%@"
    return "\n".join(
        "".join(S[(y * 19 + x * 7 + (y * x * 5) % 11) % 10] for x in range(40))
        for y in range(24)
    )


def check_tiny():
    path = "/app/tiny-source.py"
    if not os.path.exists(path):
        bad("tiny", "tiny-source.py missing")
        return
    src = open(path, "rb").read()
    if len(src) > 700:
        bad("tiny", "source %d bytes > 700" % len(src))
        return
    gz = len(gzip.compress(src))
    if gz > 400:
        bad("tiny", "gzip %d bytes > 400" % gz)
        return
    r = sh(["python3", path])
    got = r.stdout
    exp = tiny_expected() + "\n"
    if r.returncode != 0 or got != exp:
        bad("tiny", "functional output mismatch")
        return
    # must not embed the rendered data
    for line in exp.splitlines():
        if line in src.decode("latin1", "replace"):
            bad("tiny", "embeds rendered pixel rows")
            return
    try:
        rep = json.load(open("/app/compressed-sizes.json"))
    except Exception as e:
        bad("tiny", "compressed-sizes.json unreadable: %r" % e)
        return
    if rep.get("source_bytes") != len(src) or rep.get("gzip_bytes") != gz:
        bad("tiny", "size report mismatch %r vs (%d,%d)" % (rep, len(src), gz))
        return
    ok("tiny")


def main() -> int:
    print("== drift-grove verifier ==")

    # ---- main (shipped) deliverables ----
    # tile
    if os.path.exists(APP + "/fixtures/tile_initial.json"):
        spec = json.load(open(APP + "/fixtures/tile_initial.json"))
        open("/tmp/tile-in.json", "w").write(json.dumps(spec))
        check_tile("main", spec["board"], spec["goal"])
        check_tile_artifact("artifact", spec["board"], spec["goal"])
    else:
        bad("tile.main", "fixture missing")

    # expr
    if os.path.exists(APP + "/fixtures/expr_spec.json"):
        es = json.load(open(APP + "/fixtures/expr_spec.json"))
        open("/tmp/expr-spec.json", "w").write(json.dumps(es))
        check_expr("main", es["nums"], es["target"], from_file=True)
    else:
        bad("expr.main", "fixture missing")

    # oracle (main ctx)
    if os.path.exists(APP + "/fixtures/oracle_ctx.json"):
        seed = json.load(open(APP + "/fixtures/oracle_ctx.json"))["seed"]
        check_oracle("main", APP + "/fixtures/oracle_ctx.json", oracle_len(seed))
    else:
        bad("oracle.main", "fixture missing")

    # gate deliverable + regen + refusal
    if os.path.exists("/app/gate.def"):
        e = check_gate_def("/app/gate.def", 4096, 42)
        if e:
            bad("gate.main", e)
        else:
            ok("gate.main")
    else:
        bad("gate.main", "gate.def missing")
    e = check_gate_gen(4000, True)
    if e:
        bad("gate.regen", e)
    else:
        ok("gate.regen")
    e = check_gate_gen(33000, False)
    if e:
        bad("gate.refuse", e)
    else:
        ok("gate.refuse")

    # table deliverable
    if os.path.exists("/app/table.csv"):
        e = check_table_file("/app/table.csv", 8, 7, 13)
        if e:
            bad("table.main", e)
        else:
            ok("table.main")
    else:
        bad("table.main", "table.csv missing")

    # tiny
    check_tiny()

    # ---- hidden scenarios ----
    hidden = sorted(os.listdir(HID)) if os.path.isdir(HID) else []
    tiles = sorted(f for f in hidden if f.startswith("tile_"))
    exprs = sorted(f for f in hidden if f.startswith("expr_"))
    ctxs = sorted(f for f in hidden if f.startswith("ctx_"))
    tables = sorted(f for f in hidden if f.startswith("table_"))
    gates = sorted(f for f in hidden if f.startswith("gate_"))

    for f in tiles:
        spec = json.load(open(os.path.join(HID, f)))
        open("/tmp/tile-in.json", "w").write(json.dumps(spec))
        check_tile(f, spec["board"], spec["goal"])
    for f in exprs:
        es = json.load(open(os.path.join(HID, f)))
        open("/tmp/expr-spec.json", "w").write(json.dumps(es))
        check_expr(f, es["nums"], es["target"])
    for f in ctxs:
        seed = json.load(open(os.path.join(HID, f)))["seed"]
        check_oracle(f, os.path.join(HID, f), oracle_len(seed))
    for f in gates:
        g = json.load(open(os.path.join(HID, f)))
        if g.get("regen"):
            e = check_gate_gen(int(g["nbits"]), bool(g["expect_ok"]))
            if e:
                bad("gate.hidden." + f, e)
            else:
                ok("gate.hidden." + f)
    for f in tables:
        t = json.load(open(os.path.join(HID, f)))
        out = "/tmp/table-%s.csv" % f
        r = sh(["python3", "/app/gen-table.py", os.path.join(HID, f), out])
        if t.get("expect_ok", True):
            if not os.path.exists("/app/gen-table.py"):
                bad("table.hidden." + f, "gen-table.py missing")
            elif r.returncode != 0:
                bad("table.hidden." + f, "gen-table.py failed: %s" % r.stdout.strip())
            else:
                e = check_table_file(out, t["bits"], t["a"], t["b"], t["cap_rows"], t["cap_bytes"])
                if e:
                    bad("table.hidden." + f, e)
                else:
                    ok("table.hidden." + f)
        else:
            if not os.path.exists("/app/gen-table.py"):
                bad("table.hidden." + f, "gen-table.py missing")
            elif r.returncode == 0 or os.path.exists(out) or "OVER_LIMIT" not in r.stdout:
                bad("table.hidden." + f, "must refuse impossible caps")
            else:
                ok("table.hidden." + f)

    reward = 0 if FAILURES else 1
    print("RESULT: %d failures" % len(FAILURES) if FAILURES else "RESULT: all checks passed")
    print("REWARD=%d" % reward)
    return 0 if reward else 1


if __name__ == "__main__":
    sys.exit(main())