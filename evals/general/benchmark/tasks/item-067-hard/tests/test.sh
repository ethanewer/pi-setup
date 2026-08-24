#!/bin/bash
mkdir -p /logs/verifier
reward=0

if [ -f /app/interpreter.py ]; then
  passes=$(python3 - <<'PYEOF'
import subprocess

cases = [
    ("(let* ((x 2) (y (* x 3))) (+ x y))", "8"),
    ("(when (> 3 1) 10 20)", "20"),
    ("(when (< 3 1) 10)", "()"),
    ("(unless (< 3 1) 42)", "42"),
    ("(unless (> 3 1) 42)", "()"),
    ("(cond ((< 2 1) 5) ((< 1 2) 7))", "7"),
    ("(cond (#f 1) (else 9))", "9"),
    ("(cond (#f 1) (#f 2))", "()"),
    ("(case 2 ((1) 10) ((2 3) 20) (else 30))", "20"),
    ("(case 9 ((1) 10) ((2) 20))", "()"),
    ("(case (quote b) ((a) 1) ((b) 2) (else 3))", "2"),
    ("(begin (define (f n) (let* ((a n) (b (* a 2))) (cond ((> b 4) b) (else 0)))) (f 3))", "6"),
    # regression checks on pre-existing semantics
    ("(begin (define (sq x) (* x x)) (sq 12))", "144"),
    ("(let ((x 1) (y 2)) (+ x y))", "3"),
    ("(begin (define (fact n) (if (< n 2) 1 (* n (fact (- n 1))))) (fact 5))", "120"),
    ("(map (lambda (x) (* x x)) (list 1 2 3))", "(1 4 9)"),
]
ok = 0
for prog, want in cases:
    try:
        out = subprocess.run(
            ["python3", "/app/interpreter.py"], input=prog,
            capture_output=True, text=True, timeout=30).stdout.splitlines()
        got = out[0] if out else "<no output>"
        if got == want:
            ok += 1
    except Exception:
        pass
print(ok)
PYEOF
)
  total=16
  if [ "$passes" = "$total" ]; then
    reward=1
  elif [ "$passes" -ge 12 ]; then
    reward=0.5
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
