#!/bin/bash
# Oracle for willow-quill: author the pipeline module (closures, currying,
# variadic composition, mutually recursive scanner) and run it on the visible
# script to produce /app/answer.json. Never reads /tests.
set -eu

cat > /app/pipeline.py <<'PY'
"""willow-quill audit bench: self-observing closures, currying, variadic
composition, and a mutually recursive bracket scanner."""

# ---- 1. Stateful ledger closure --------------------------------------------

def make_ledger(start=0):
    balance = start
    log = []

    def ledger(command, *args):
        nonlocal balance
        if command == "deposit" or command == "withdraw":
            if len(args) != 1:
                raise ValueError("ledger: %s needs exactly one amount" % command)
            n = args[0]
            if command == "deposit":
                balance += n
            else:
                balance -= n
            log.append((command, n))
            return balance
        if command == "balance":
            return balance
        if command == "log":
            return tuple(log)
        if command == "undo":
            if log:
                cmd, n = log.pop()
                if cmd == "deposit":
                    balance -= n
                else:
                    balance += n
            return balance
        raise ValueError("ledger: unknown command %r" % (command,))

    return ledger


# ---- 2. Currying ------------------------------------------------------------

def curry3(f):
    def g(a):
        def h(b):
            def k(c):
                return f(a, b, c)
            return k
        return h
    return g


# ---- 3. Variadic left-to-right composition ----------------------------------

def chain(*fns):
    def h(x):
        for fn in fns:
            x = fn(x)
        return x
    return h


# ---- 4. Mutually recursive pyrite scanner ------------------------------------

OPENERS = {"(": ")", "[": "]"}
CLOSERS = {")": "(", "]": "["}


def _scan_paren(s, i, depth):
    """Scan from index i inside a '(...)' group opened just before i.
    Returns (index after the closing ')', max depth reached)."""
    best = depth
    while i < len(s):
        ch = s[i]
        if ch == "(":
            j, d = _scan_paren(s, i + 1, depth + 1)
            best = max(best, d)
            i = j
        elif ch == "[":
            j, d = _scan_brack(s, i + 1, depth + 1)
            best = max(best, d)
            i = j
        elif ch == ")":
            return i + 1, best
        elif ch == "]":
            raise ValueError("mismatched bracket")
        else:
            raise ValueError("invalid character %r" % ch)
    raise ValueError("unbalanced: unterminated '('")


def _scan_brack(s, i, depth):
    """Scan from index i inside a '[...]' group opened just before i.
    Returns (index after the closing ']', max depth reached)."""
    best = depth
    while i < len(s):
        ch = s[i]
        if ch == "(":
            j, d = _scan_paren(s, i + 1, depth + 1)
            best = max(best, d)
            i = j
        elif ch == "[":
            j, d = _scan_brack(s, i + 1, depth + 1)
            best = max(best, d)
            i = j
        elif ch == "]":
            return i + 1, best
        elif ch == ")":
            raise ValueError("mismatched bracket")
        else:
            raise ValueError("invalid character %r" % ch)
    raise ValueError("unbalanced: unterminated '['")


def _scan_toplevel(s):
    """Scan a whole pyrite string at depth 0. Returns max depth or raises."""
    best = 0
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == "(":
            j, d = _scan_paren(s, i + 1, 1)
            best = max(best, d)
            i = j
        elif ch == "[":
            j, d = _scan_brack(s, i + 1, 1)
            best = max(best, d)
            i = j
        else:
            raise ValueError("stray %r at top level" % ch)
    return best


def pyrite_balanced(s):
    try:
        _scan_toplevel(s)
        return True
    except ValueError:
        return False


def pyrite_depth(s):
    return _scan_toplevel(s)


# ---- 5. Variadic self-observing probe ----------------------------------------

def make_probe():
    state = {"n": 0, "prev": None}

    def probe(*vals):
        state["n"] += 1
        out = (max(vals) - min(vals)) if vals else 0
        result = {"n": state["n"], "prev": state["prev"], "out": out}
        state["prev"] = tuple(vals)
        return result

    return probe


# ---- 6. Script driver ---------------------------------------------------------

def _run_script(path):
    ledger = make_ledger(0)
    probe = make_probe()
    results = []

    def combiner(a, b, c):
        return a * 100 + b * 10 + c

    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            tokens = raw.split()
            if not tokens or tokens[0].startswith("#"):
                continue
            head = tokens[0]
            if head == "ledger":
                cmd = tokens[1]
                if cmd in ("deposit", "withdraw"):
                    results.append(ledger(cmd, int(tokens[2])))
                else:
                    results.append(ledger(cmd))
            elif head == "curry":
                a, b, c = (int(t) for t in tokens[1:4])
                results.append(curry3(combiner)(a)(b)(c))
            elif head == "chain":
                exprs, x = tokens[1:-1], int(tokens[-1])
                fns = [eval("lambda x: (" + e + ")", {"__builtins__": {}})
                       for e in exprs]
                results.append(chain(*fns)(x))
            elif head == "pyrite":
                try:
                    results.append(pyrite_depth(tokens[1]))
                except ValueError:
                    results.append("error")
            elif head == "probe":
                vals = tuple(int(t) for t in tokens[1:])
                results.append(probe(*vals))
    return {"results": results, "count": len(results)}


def main():
    import json
    answer = _run_script("/app/script.txt")
    with open("/app/answer.json", "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2)


if __name__ == "__main__":
    main()
PY

python3 /app/pipeline.py

echo "solve.sh done"
ls -l /app/pipeline.py /app/answer.json
