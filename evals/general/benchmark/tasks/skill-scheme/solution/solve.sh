#!/bin/bash
set -euo pipefail

cat > /app/scheme_prog.scm <<'EOF'
(define (square x) (* x x))
(define (sumsq n)
  (if (= n 0) 0
      (+ (square n) (sumsq (- n 1)))))
(define (count-even lst)
  (if (null? lst) 0
      (if (= 0 (mod (car lst) 2))
          (+ 1 (count-even (cdr lst)))
          (count-even (cdr lst)))))
(sumsq 5)
(count-even (list 3 1 4 1 5 9 2 6))
EOF

python3 /app/sceval.py /app/scheme_prog.scm > /app/scheme_out.txt