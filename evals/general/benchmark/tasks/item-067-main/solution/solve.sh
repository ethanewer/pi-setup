#!/bin/bash
# Oracle solution for item-067-main: extend /app/interpreter.py with cond/and/or
# at the extension point, then self-check against the verifier cases.
set -euo pipefail

python3 - <<'PY'
# Deterministically patch the extension point in /app/interpreter.py.
src = open("/app/interpreter.py").read()
anchor = "        # application\n"
block = '''        if opn == 'cond':
            for clause in expr[1:]:
                test = clause[0]
                if isinstance(test, Sym) and test.name == 'else':
                    return eval_(clause[1], env)
                if is_true(eval_(test, env)):
                    return eval_(clause[1], env)
            return NIL
        if opn == 'and':
            if not expr[1:]:
                return True
            for e in expr[1:]:
                v = eval_(e, env)
                if not is_true(v):
                    return v
            return eval_(expr[-1], env)
        if opn == 'or':
            for e in expr[1:]:
                v = eval_(e, env)
                if is_true(v):
                    return v
            return False
'''

assert src.count(anchor) == 1, "anchor not unique"
assert "opn == 'cond'" not in src, "already patched"
patched = src.replace(anchor, block + anchor, 1)
open("/app/interpreter.py", "w").write(patched)
print("patched interpreter.py")
PY

python3 - <<'PY'
import subprocess, sys

def run(prog):
    r = subprocess.run([sys.executable, "/app/interpreter.py"],
                       input=prog.encode(), capture_output=True)
    return r.stdout.decode().strip()

cases = [
    ("(cond ((< 2 1) 5) ((< 1 2) 7))", "7"),
    ("(cond (#f 1) (else 9))", "9"),
    ("(cond (#f 1) (#f 2))", "()"),
    ("(and #t (> 3 2))", "#t"),
    ("(and #t (< 1 0) 5)", "#f"),
    ("(or #f #f)", "#f"),
    ("(or #f 5 #t)", "5"),
    ("(if (> 3 2) 100 200)", "100"),
    ("(let ((x 5)) (begin (define (f a) (* a 2)) (f x)))", "10"),
]
ok = True
for prog, exp in cases:
    got = run(prog)
    if got != exp:
        ok = False
    print(f"{'OK' if got == exp else 'FAIL'}: {prog!r} -> {got!r} (exp {exp!r})")
sys.exit(0 if ok else 1)
PY
echo "self-check done"