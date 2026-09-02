(define (make-adder x) (lambda (y) (+ x y)))
((make-adder 10) 5)
