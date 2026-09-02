#!/bin/bash
# Verifier for opal-delta: checks the visible /app/expression.txt against the
# shipped config, then EXECUTES /app/solver.py on hidden configs and validates
# every expression with an independent parser (allowed-number membership,
# one-use-per-occurrence, exact evaluation, IMPOSSIBLE correctness).
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import ast, json, os, subprocess, sys
from collections import Counter

failures = []

def load_json(p):
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)

def reachable_targets(allowed):
    """Independent brute force: all values from every non-empty subset of
    occurrences, ops + - *, each occurrence used exactly once."""
    n = len(allowed)
    dp = {}
    for i in range(n):
        dp[1 << i] = {allowed[i]}
    for mask in range(1, 1 << n):
        if mask not in dp:
            dp[mask] = set()
        if mask & (mask - 1) == 0:
            continue
        sub = (mask - 1) & mask
        while sub > 0:
            other = mask ^ sub
            if other:
                for a in dp.get(sub, ()):
                    for b in dp.get(other, ()):
                        dp[mask].update((a + b, a - b, b - a, a * b))
            sub = (sub - 1) & mask
    out = set()
    for mask, vals in dp.items():
        out |= vals
    return out

def check_expression(path, cfg, tag):
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        failures.append("%s: %s missing or empty" % (tag, path))
        return
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except Exception as e:
        failures.append("%s: unreadable: %r" % (tag, e))
        return
    lines = [l for l in text.splitlines() if l.strip()]
    if len(lines) != 1:
        failures.append("%s: expression.txt must contain exactly one line" % tag)
        return
    expr = lines[0].strip()
    allowed = [int(v) for v in cfg["allowed"]]
    target = int(cfg["target"])
    possible = target in reachable_targets(allowed)

    if expr == "IMPOSSIBLE":
        if possible:
            failures.append("%s: wrote IMPOSSIBLE but target %d is reachable"
                            % (tag, target))
        return
    if not possible:
        failures.append("%s: wrote an expression but no valid one exists?!"
                        % tag)
        return
    # parse with ast, whitelisting node types
    try:
        tree = ast.parse(expr, mode="eval")
    except Exception as e:
        failures.append("%s: unparsable expression %r: %r" % (tag, expr, e))
        return
    used = Counter()
    def visit(node):
        if isinstance(node, ast.Expression):
            visit(node.body)
        elif isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult)):
            visit(node.left); visit(node.right)
        elif isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            visit(node.operand)
        elif isinstance(node, ast.Constant) and isinstance(node.value, int) and not isinstance(node.value, bool):
            tok = ast.dump(node)
            used[node.value] += 1
        else:
            raise ValueError("disallowed node %s" % type(node).__name__)
    try:
        visit(tree)
    except Exception as e:
        failures.append("%s: invalid expression %r: %s" % (tag, expr, e))
        return
    pool = Counter(allowed)
    for v, cnt in used.items():
        if cnt > pool.get(v, 0):
            failures.append("%s: literal %r used %d times but pool allows %d"
                            % (tag, v, cnt, pool.get(v, 0)))
            return
    if not used:
        failures.append("%s: expression uses no numbers" % tag)
        return
    try:
        val = eval(compile(tree, "<expr>", "eval"))
    except Exception as e:
        failures.append("%s: evaluation failed: %r" % (tag, e))
        return
    if val != target:
        failures.append("%s: expression %r evaluates to %r, want %d"
                        % (tag, expr, val, target))

if not os.path.isfile("/app/solver.py"):
    failures.append("missing /app/solver.py")

# visible deliverable
if os.path.isfile("/app/config.json"):
    check_expression("/app/expression.txt", load_json("/app/config.json"), "visible")
else:
    failures.append("no-modify: /app/config.json missing")

# hidden cases: execute the solver unchanged
hidden_dir = "/tests/hidden"
for case in sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []:
    base = os.path.join(hidden_dir, case)
    cfg_path = os.path.join(base, "config.json")
    if not os.path.isfile(cfg_path):
        failures.append("hidden %r: no config.json" % case)
        continue
    outdir = "/tmp/opal_delta_%s" % case
    subprocess.run(["rm", "-rf", outdir], check=False)
    try:
        r = subprocess.run([sys.executable, "/app/solver.py", cfg_path, outdir],
                           capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        failures.append("hidden %r: solver timed out" % case)
        continue
    if r.returncode != 0:
        failures.append("hidden %r: solver failed rc=%s err=%.300s"
                        % (case, r.returncode, r.stderr))
        continue
    check_expression(os.path.join(outdir, "expression.txt"),
                     load_json(cfg_path), "hidden/%s" % case)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
