(define make-fib (lambda (self) (lambda (n) (if (< n 2) n (+ ((self self) (- n 1)) ((self self) (- n 2)))))))
(define fib (lambda (n) ((make-fib make-fib) n)))
(print (fib 12))
(print (+ (fib 6) 1))
