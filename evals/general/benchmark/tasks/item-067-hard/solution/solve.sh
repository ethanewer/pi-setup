#!/bin/bash
set -euo pipefail

python3 - <<'PYEOF'
src = open('/app/interpreter.py').read()

marker = "        # === EXTENSION POINT ==="
assert marker in src

extension = '''        # === EXTENSION POINT ===
        if opn == 'let*':
            new = Env(parent=env)
            for b in expr[1]:
                new.set(b[0].name, eval_(b[1], new))
            result = NIL
            for e in expr[2:]:
                result = eval_(e, new)
            return result
        if opn == 'when':
            if is_true(eval_(expr[1], env)):
                result = NIL
                for e in expr[2:]:
                    result = eval_(e, env)
                return result
            return NIL
        if opn == 'unless':
            if not is_true(eval_(expr[1], env)):
                result = NIL
                for e in expr[2:]:
                    result = eval_(e, env)
                return result
            return NIL
        if opn == 'cond':
            for clause in expr[1:]:
                test = clause[0]
                if isinstance(test, Sym) and test.name == 'else':
                    return eval_(clause[1], env)
                if is_true(eval_(test, env)):
                    return eval_(clause[1], env)
            return NIL
        if opn == 'case':
            key = eval_(expr[1], env)
            for clause in expr[2:]:
                head = clause[0]
                if isinstance(head, Sym) and head.name == 'else':
                    return eval_(clause[1], env)
                for d in head:
                    if d == key or (isinstance(d, Sym) and isinstance(key, Sym) and d.name == key.name):
                        return eval_(clause[1], env)
            return NIL
'''

src = src.replace(marker, extension, 1)
open('/app/interpreter.py', 'w').write(src)
PYEOF

# Self-test all cases from the instruction
python3 - <<'PYEOF'
import subprocess

cases = [
    ("(let* ((x 2) (y (* x 3))) (+ x y))", "8"),
    ("(when (> 3 1) 10 20)", "20"),
    ("(when (< 3 1) 10)", "()"),
    ("(unless (< 3 1) 42)", "42"),
    ("(cond ((< 2 1) 5) ((< 1 2) 7))", "7"),
    ("(cond (#f 1) (else 9))", "9"),
    ("(case 2 ((1) 10) ((2 3) 20) (else 30))", "20"),
    ("(case 9 ((1) 10) ((2) 20))", "()"),
    ("(begin (define (f n) (let* ((a n) (b (* a 2))) (cond ((> b 4) b) (else 0)))) (f 3))", "6"),
    # regression: existing forms unchanged
    ("(begin (define (sq x) (* x x)) (sq 12))", "144"),
    ("(let ((x 1) (y 2)) (+ x y))", "3"),
]
for prog, want in cases:
    out = subprocess.run(
        ["python3", "/app/interpreter.py"], input=prog,
        capture_output=True, text=True).stdout.splitlines()
    got = out[0] if out else "<no output>"
    assert got == want, (prog, want, got)
print("all self-tests pass")
PYEOF
