#!/bin/bash
# Verifier for umber-gasket. Exercises all four deliverables on hidden inputs,
# then writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
python3 - <<'PYEOF' >&2
import json
import math
import os
import re
import subprocess

failures = []
H = "/tests/hidden"


def log(*a):
    print("[verifier]", *a)


def can(path):
    return os.path.exists(path)


def ref_legal_moves(fen):
    """Independent geometric reference for the lone white knight."""
    try:
        board_part = fen.split()[0]
        ranks = board_part.split("/")
    except Exception:
        return [], None
    if len(ranks) != 8:
        return [], "bad-rank-count"
    board = []
    for rank in ranks:
        row = []
        for ch in rank:
            if ch.isdigit():
                row += ["."] * int(ch)
            else:
                row.append(ch)
        if len(row) != 8:
            return [], "bad-row-length"
        board.append(row)
    sr = sc = None
    ncount = 0
    for r in range(8):
        for c in range(8):
            if board[r][c] == "N":
                sr, sc = r, c
                ncount += 1
    if ncount == 0:
        return [], None
    if ncount > 1:
        return [], "more-than-one-knight"
    moves = [(2,1),(2,-1),(-2,1),(-2,-1),(1,2),(1,-2),(-1,2),(-1,-2)]
    out = []
    for dr, dc in moves:
        nr, nc = sr + dr, sc + dc
        if 0 <= nr < 8 and 0 <= nc < 8 and board[nr][nc] == ".":
            b2 = [list(x) for x in board]
            b2[sr][sc] = "."
            b2[nr][nc] = "N"
            out.append(b2)
    return [b2_to_fen(b) for b in out], None


def b2_to_fen(board):
    ranks = []
    for row in board:
        s = []
        cnt = 0
        for ch in row:
            if ch == ".":
                cnt += 1
            else:
                if cnt:
                    s.append(str(cnt)); cnt = 0
                s.append(ch)
        if cnt:
            s.append(str(cnt))
        ranks.append("".join(s))
    return "/".join(ranks) + " w - - 0 1"


def net_value(n):
    F = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144]
    return F[math.isqrt(n)]


def direkt(ast):
    """Reference AST evaluator for the hidden M self-interpreter subjects."""
    if isinstance(ast, int):
        return ast
    op = ast[0]
    if op in ("+", "-", "*", "/"):
        a, b = direkt(ast[1]), direkt(ast[2])
        return {"+": lambda: a+b, "-": lambda: a-b,
                "*": lambda: a*b, "/": lambda: a//b}[op]()
    if op == "sq":
        v = direkt(ast[1])
        return v * v
    if op == "cub":
        v = direkt(ast[1])
        return v * v * v
    if op == "twice":
        return 2 * direkt(ast[1])
    if op == "if":
        cond = ast[1]
        p = cond[0]
        a, b = direkt(cond[1]), direkt(cond[2])
        t = {"<": a < b, "<=": a <= b, ">": a > b,
             ">=": a >= b, "=": a == b}[p]
        return direkt(ast[2]) if t else direkt(ast[3])
    return None


def run_proc(args, stdin_bytes):
    try:
        p = subprocess.run(args, input=stdin_bytes, capture_output=True,
                           timeout=60)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except Exception as e:
        return -1, "raise:%r" % e


# ------------------------------------------------------------------ eval.py
def check_eval():
    if not can("/app/eval.py"):
        failures.append("eval.py missing")
        return
    manifest = json.load(open(os.path.join(H, "eval.json")))
    # relay case
    r = manifest["relay"]
    program = os.path.join(H, r["program"].replace("m/", "m/"))
    # verify path exists under /tests/hidden/m
    prog_path = os.path.join(H, r["program"])
    if not os.path.exists(prog_path):
        failures.append("eval relay: hidden program missing %s" % prog_path)
        return
    relay = r["input"]
    stdin = "\n".join([prog_path] + relay) + "\n"
    rc, out = run_prog(["python3", "/app/eval.py"], stdin.encode())
    expected = [str(sum(int(x) for x in relay))]
    got = out.splitlines()
    if got != expected:
        failures.append("eval relay: got %r want %r (rc=%s)" % (got, expected, rc))
    # META programs: output must equal direct value of subject
    for item in manifest["meta"]:
        mp = os.path.join(H, item["program"])
        if not os.path.exists(mp):
            failures.append("eval meta: hidden program missing %s" % mp)
            continue
        rc, out = run_prog(["python3", "/app/eval.py"], mp + "\n")
        exp = [str(direkt(item["subject"]))]
        got = out.splitlines()
        if got != exp:
            failures.append("eval %s: got %r expected %r"
                            % (item["program"], got, exp))


def run_prog(args, stdin):
    try:
        p = subprocess.run(args, input=stdin.encode() if isinstance(stdin, str) else stdin,
                           capture_output=True, timeout=60)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except Exception as e:
        return -1, "raise:%r" % e


# --------------------------------------------------------- moves.fen.rules
def engine_moves(fen, rules):
    out = set()
    for pat, repl in rules:
        try:
            if re.fullmatch(re.escape(pat), fen):
                out.add(repl)
        except Exception:
            continue
    out.discard(fen)
    return out


def check_moves():
    if not can("/app/moves.fen.rules"):
        failures.append("moves.fen.rules missing")
        return
    try:
        rules = json.load(open("/app/moves.fen.rules"))
    except Exception as e:
        failures.append("moves.fen.rules not valid JSON: %r" % e)
        return
    if not isinstance(rules, list) or not rules:
        failures.append("moves.fen.rules: not a non-empty list")
        return
    for r_ in rules:
        if not (isinstance(r_, list) and len(r_) == 2 and
                isinstance(r_[0], str) and isinstance(r_[1], str)):
            failures.append("moves.fen.rules: not list of [str, str]")
            return
    fens = json.load(open(os.path.join(H, "fens.json")))
    for fen in fens:
        expected, err = ref_legal_moves(fen)
        if err:
            failures.append("moves ref error %s: %s" % (fen, err))
            continue
        got = sorted(engine_moves(fen, rules))
        exp = sorted(expected)
        if got != list(exp):
            failures.append("moves fen '%s': got=%d lines want %d"
                            % (fen, len(got), len(exp)))
            continue
        if len(got) != len(set(got)):
            failures.append("moves: duplicate output for %s" % fen)
        if got != exp:
            failures.append("moves: set mismatch for %s" % fen)
        if fen in got:
            failures.append("moves: starter emitted for %s" % fen)


# ----------------------------------------------------------- gate_net / simulate
def ref_parse_net(text):
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    ins = lines[0].split()[1:]
    outs = lines[1].split()[1:]
    expr = {}
    for ln in lines[2:]:
        lhs, sep, rest = ln.partition("=")
        if sep:
            expr[lhs.strip()] = rest.strip()
    return ins, outs, expr


def ref_eval_net(text, n):
    ins, outs, expr = ref_parse_net(text)
    memo = {}
    for i, name in enumerate(ins):
        memo[name] = (n >> i) & 1

    def solve(w):
        if w in memo:
            return memo[w]
        ws = expr[w].split()
        if len(ws) == 1 and ws[0] in ("0", "1"):
            v = int(ws[0])
        elif len(ws) == 1:
            v = solve(ws[0])
        elif ws[0] == "~":
            v = 1 - solve(ws[1])
        else:
            a = solve(ws[1]); b = solve(ws[2])
            v = (a & b) if ws[0] == "&" else ((a | b) if ws[0] == "|" else (a ^ b))
        memo[w] = v
        return v

    res = 0
    for i, o in enumerate(outs):
        res |= solve(o) << i
    return res


def check_gate():
    if not can("/app/gate_net.txt"):
        failures.append("gate_net.txt missing")
        return
    if not can("/app/simulate.py"):
        failures.append("simulate.py missing")
        return
    text = open("/app/gate_net.txt").read()
    try:
        ins, outs, expr = ref_parse_net(text)
    except Exception as e:
        failures.append("gate_net.txt parse error: %r" % e)
        return
    vals = json.load(open(os.path.join(H, "gates.json")))
    for n in vals:
        try:
            got = ref_eval_net(text, n)
        except Exception as e:
            failures.append("gate_net ref eval n=%d raised %r" % (n, e))
            continue
        exp = net_value(n)
        if got != exp:
            failures.append("gate_net(ref): n=%d got %d want %d" % (n, got, exp))
        # simulate.py must agree
        rc, so = run_prog(["python3", "/app/simulate.py", "/app/gate_net.txt", str(n)], "")
        out = so.strip()
        if out != str(exp):
            failures.append("simulate %d: stdout=%r want %d" % (n, so.strip(), exp))
        elif rc != 0:
            failures.append("simulate %d: returncode %d" % (n, rc))


check_eval()
check_moves()
check_gate()

reward = 0 if failures else 1
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("%d\n" % reward)
print("reward=%d failures=%d" % (reward, len(failures)))
for f in failures[:60]:
    print("  -", f)
PYEOF