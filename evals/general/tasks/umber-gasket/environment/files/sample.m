; A tiny M example. eval.py expects the program file's path as the first line
; of stdin; remaining lines are relayed to this program's (read-int)/(read).
(define total
  (lambda (a)
    (if (eof?) a (total (+ a (read-int))))))
(define double (lambda (x) (* 2 x)))
(print (total 0))
(print (double (read-int)))
