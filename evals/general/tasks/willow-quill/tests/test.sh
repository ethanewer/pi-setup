#!/bin/bash
# Verifier for willow-quill: enforces the no-modify rule on /app/script.txt,
# checks the visible deliverables (pipeline.py + answer.json recomputed from
# the script), and EXECUTES the deliverable module's API on hidden probe
# cases against an independent reference implementation. Writes REWARD (0/1)
# to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

SCRIPT_SHA="$(sha256sum /app/script.txt 2>/dev/null | awk '{print $1}')"
python3 - "$SCRIPT_SHA" <<'PY'
import importlib.util, json, os, subprocess, sys

MODULE = "/app/pipeline.py"
ANSWER = "/app/answer.json"
SCRIPT = "/app/script.txt"
HIDDEN = "/tests/hidden"

failures = []

# --- no-modify on the visible script ----------------------------------------
PRISTINE_SHA = None  # filled by the bash section below via argv[1]
PRISTINE_SHA = sys.argv[1] if len(sys.argv) > 1 else None
if PRISTINE_SHA:
    import hashlib
    if not os.path.isfile(SCRIPT):
        failures.append("fixture /app/script.txt missing")
    else:
        got = hashlib.sha256(open(SCRIPT, "rb").read()).hexdigest()
        if got != PRISTINE_SHA:
            failures.append("/app/script.txt was modified")

# --- independent reference implementation ------------------------------------
def ref_make_ledger(start=0):
    balance = start
    log = []

    def ledger(command, *args):
        nonlocal balance
        if command in ("deposit", "withdraw"):
            if len(args) != 1:
                raise ValueError("needs exactly one amount")
            n = args[0]
            balance = balance + n if command == "deposit" else balance - n
            log.append((command, n))
            return balance
        if command == "balance":
            return balance
        if command == "log":
            return tuple(log)
        if command == "undo":
            if log:
                cmd, n = log.pop()
                balance = balance - n if cmd == "deposit" else balance + n
            return balance
        raise ValueError("unknown command")

    return ledger


def ref_curry3(f):
    def g(a):
        def h(b):
            def k(c):
                return f(a, b, c)
            return k
        return h
    return g


def ref_chain(*fns):
    def h(x):
        for fn in fns:
            x = fn(x)
        return x
    return h


def ref_pyrite_balanced(s):
    pairs = {"(": ")", "[": "]"}
    close_of = {")": "(", "]": "["}
    stack = []
    for ch in s:
        if ch in pairs:
            stack.append(ch)
        elif ch in close_of:
            if not stack or stack[-1] != close_of[ch]:
                return False
            stack.pop()
        else:
            raise ValueError("bad char")
    return not stack


def ref_pyrite_depth(s):
    if not ref_pyrite_balanced(s):
        raise ValueError("unbalanced")
    best = depth = 0
    for ch in s:
        if ch in "([":
            depth += 1
            best = max(best, depth)
        elif ch in ")]":
            depth -= 1
    return best


def ref_make_probe():
    st = {"n": 0, "prev": None}

    def probe(*vals):
        st["n"] += 1
        out = (max(vals) - min(vals)) if vals else 0
        res = {"n": st["n"], "prev": st["prev"], "out": out}
        st["prev"] = tuple(vals)
        return res

    return probe


def norm(x):
    """Normalize so tuples become lists and comparisons are strict."""
    if isinstance(x, tuple):
        return [norm(v) for v in x]
    if isinstance(x, list):
        return [norm(v) for v in x]
    if isinstance(x, dict):
        return {k: norm(v) for k, v in x.items()}
    return x


def ref_result(value):
    try:
        return norm(value)
    except Exception:
        return "error"


# --- visible script -> expected answer ---------------------------------------
def ref_script_results(path):
    ledger = ref_make_ledger(0)
    probe = ref_make_probe()
    results = []

    def combiner(a, b, c):
        return a * 100 + b * 10 + c

    for raw in open(path):
        tokens = raw.split()
        if not tokens or tokens[0].startswith("#"):
            continue
        head = tokens[0]
        if head == "ledger":
            cmd = tokens[1]
            if cmd in ("deposit", "withdraw"):
                results.append(ref_result(ledger(cmd, int(tokens[2]))))
            else:
                results.append(ref_result(ledger(cmd)))
        elif head == "curry":
            a, b, c = (int(t) for t in tokens[1:4])
            results.append(ref_result(ref_curry3(combiner)(a)(b)(c)))
        elif head == "chain":
            exprs, x = tokens[1:-1], int(tokens[-1])
            fns = [eval("lambda x: (" + e + ")", {"__builtins__": {}})
                   for e in exprs]
            results.append(ref_result(ref_chain(*fns)(x)))
        elif head == "pyrite":
            try:
                results.append(ref_result(ref_pyrite_depth(tokens[1])))
            except ValueError:
                results.append("error")
        elif head == "probe":
            vals = tuple(int(t) for t in tokens[1:])
            results.append(ref_result(probe(*vals)))
    return results


expected_results = None
if os.path.isfile(SCRIPT):
    try:
        expected_results = ref_script_results(SCRIPT)
    except Exception as e:
        failures.append("reference script evaluation failed: %s" % e)

# --- import the deliverable module -------------------------------------------
mod = None
if not os.path.isfile(MODULE):
    failures.append("missing deliverable %s" % MODULE)
else:
    try:
        spec = importlib.util.spec_from_file_location("pipeline", MODULE)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception as e:
        failures.append("pipeline.py failed to import: %s" % e)
        mod = None

# --- answer.json vs reference -------------------------------------------------
if not os.path.isfile(ANSWER):
    failures.append("missing deliverable %s" % ANSWER)
elif expected_results is not None:
    try:
        got = json.load(open(ANSWER))
        if not isinstance(got, dict) or "results" not in got:
            failures.append("answer.json has wrong shape")
        elif norm(got["results"]) != expected_results:
            failures.append("answer.json results mismatch")
        elif got.get("count") != len(expected_results):
            failures.append("answer.json count mismatch")
    except Exception as e:
        failures.append("answer.json unreadable: %s" % e)

# --- hidden probe cases --------------------------------------------------------
def run_ops(case):
    """Execute one hidden case; returns list of normalized results."""
    out = []
    ledger = mod.make_ledger()
    probe = mod.make_probe()
    for op in case["ops"]:
        kind = op["op"]
        try:
            if kind == "ledger":
                ledger = mod.make_ledger(op.get("start", 0))
                for step in op["seq"]:
                    cmd = step[0] if step else ""
                    try:
                        if cmd in ("deposit", "withdraw"):
                            out.append(ref_result(ledger(cmd, step[1])))
                        else:
                            out.append(ref_result(ledger(cmd)))
                    except Exception:
                        out.append("error")
            elif kind == "curry":
                f = eval("lambda a, b, c: (" + op["f"] + ")",
                         {"__builtins__": {}})
                a, b, c = op["args"]
                out.append(ref_result(mod.curry3(f)(a)(b)(c)))
            elif kind == "chain":
                fns = [eval("lambda x: (" + e + ")", {"__builtins__": {}})
                       for e in op["fs"]]
                out.append(ref_result(mod.chain(*fns)(op["x"])))
            elif kind == "balanced":
                out.append(ref_result(mod.pyrite_balanced(op["s"])))
            elif kind == "depth":
                try:
                    out.append(ref_result(mod.pyrite_depth(op["s"])))
                except ValueError:
                    out.append("error")
            elif kind == "probe":
                probe = mod.make_probe()
                for vals in op["seq"]:
                    out.append(ref_result(probe(*vals)))
            else:
                failures.append("unknown op kind %r in hidden case" % kind)
        except Exception as e:
            failures.append("hidden op %r crashed: %s" % (kind, e))
            out.append("exception")
    return out


def ref_ops(case):
    out = []
    for op in case["ops"]:
        kind = op["op"]
        if kind == "ledger":
            ledger = ref_make_ledger(op.get("start", 0))
            for step in op["seq"]:
                cmd = step[0]
                try:
                    if cmd in ("deposit", "withdraw"):
                        out.append(ref_result(ledger(cmd, step[1])))
                    else:
                        out.append(ref_result(ledger(cmd)))
                except Exception:
                    out.append("error")
        elif kind == "curry":
            f = eval("lambda a, b, c: (" + op["f"] + ")", {"__builtins__": {}})
            a, b, c = op["args"]
            out.append(ref_result(ref_curry3(f)(a)(b)(c)))
        elif kind == "chain":
            fns = [eval("lambda x: (" + e + ")", {"__builtins__": {}})
                   for e in op["fs"]]
            out.append(ref_result(ref_chain(*fns)(op["x"])))
        elif kind == "balanced":
            try:
                out.append(ref_result(ref_pyrite_balanced(op["s"])))
            except Exception:
                out.append("error")
        elif kind == "depth":
            try:
                out.append(ref_result(ref_pyrite_depth(op["s"])))
            except Exception:
                out.append("error")
        elif kind == "probe":
            probe = ref_make_probe()
            for vals in op["seq"]:
                out.append(ref_result(probe(*vals)))
    return out


hidden = sorted(os.listdir(HIDDEN)) if os.path.isdir(HIDDEN) else []
if not hidden:
    failures.append("no hidden cases present")
for case_name in hidden:
    p = os.path.join(HIDDEN, case_name, "probes.json")
    if not os.path.isfile(p):
        failures.append("hidden '%s' malformed" % case_name)
        continue
    try:
        case = json.load(open(p))
    except Exception as e:
        failures.append("hidden '%s': unreadable probes.json (%s)" % (case_name, e))
        continue
    if mod is None:
        failures.append("hidden '%s': module unavailable" % case_name)
        continue
    want = ref_ops(case)
    got = run_ops(case)
    if got != want:
        failures.append("hidden '%s': results mismatch (got %r want %r)"
                        % (case_name, got, want))

# --- module must also run as a script ------------------------------------------
if os.path.isfile(MODULE):
    r = subprocess.run([sys.executable, MODULE], capture_output=True,
                       text=True, timeout=120)
    if r.returncode != 0:
        failures.append("python3 /app/pipeline.py exited %d" % r.returncode)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
