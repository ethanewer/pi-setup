#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/interpreter.py ]; then
  if python3 - <<'PYEOF'
import subprocess, sys
def run(prog):
    r = subprocess.run([sys.executable, '/app/interpreter.py'],
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
for prog, exp in cases:
    assert run(prog) == exp, (prog, run(prog), exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt