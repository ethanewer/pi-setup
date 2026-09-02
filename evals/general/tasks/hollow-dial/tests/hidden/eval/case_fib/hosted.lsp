;; Liz meta-circular evaluator: two nesting levels of interpretation.
(define primitives (quote (+ - * quotient remainder = < > <= >= cons car cdr null? pair? symbol? number? eq? not list print)))

(define (memq? x items)
  (if (null? items) #f
      (if (eq? x (car items)) #t (memq? x (cdr items)))))

(define (lookup name env)
  (if (null? env) name
      (if (eq? name (car (car env))) (cdr (car env))
          (lookup name (cdr env)))))

(define (self-eval? e)
  (if (number? e) #t
      (if (eq? e (quote ())) #t
          (if (eq? e #t) #t (if (eq? e #f) #t #f)))))

(define (define-in env name val) (cons (cons name val) env))

(define (extend env params args)
  (if (null? params) env
      (cons (cons (car params) (car args)) (extend env (cdr params) (cdr args)))))

(define (ev-begin forms env)
  (if (null? forms) #f
      (if (null? (cdr forms)) (ev (car forms) env)
          (begin (ev (car forms) env) (ev-begin (cdr forms) env)))))

(define (ev-list es env)
  (if (null? es) (quote ())
      (cons (ev (car es) env) (ev-list (cdr es) env))))

(define (ev e env)
  (if (self-eval? e) e
      (if (symbol? e) (lookup e env)
          (if (null? e) (quote err-null)
              (if (eq? (car e) (quote quote)) (car (cdr e))
                  (if (eq? (car e) (quote if))
                      (if (ev (car (cdr e)) env)
                          (ev (car (cdr (cdr e))) env)
                          (ev (car (cdr (cdr (cdr e)))) env))
                      (if (eq? (car e) (quote define))
                          (define-in env (car (cdr e)) (ev (car (cdr (cdr e))) env))
                          (if (eq? (car e) (quote lambda))
                              (cons (quote closure)
                                    (cons env (cons (car (cdr e)) (cdr (cdr e)))))
                              (if (eq? (car e) (quote begin))
                                  (ev-begin (cdr e) env)
                                  (apply2 (ev (car e) env) (ev-list (cdr e) env)))))))))))

(define (apply2 f args)
  (if (pair? f)
      (if (eq? (car f) (quote closure))
          (ev-begin (cdr (cdr (cdr f)))
                    (extend (car (cdr f)) (car (cdr (cdr f))) args))
          (quote err-closure))
      (if (memq? f primitives)
          (prim-eval f args)
          (quote err-bad-proc))))

(define (eval-top e env)
  (if (pair? e)
      (if (eq? (car e) (quote define))
          (ev e env)
          (begin (ev e env) env))
      (begin (ev e env) env)))

(define (run-tail forms env)
  (if (null? forms) #t
      (run-tail (cdr forms) (eval-top (car forms) env))))

(define (run-prog forms) (run-tail forms (quote ())))

(run-prog (quote (
  (define make-fib (lambda (self) (lambda (n) (if (< n 2) n (+ ((self self) (- n 1)) ((self self) (- n 2)))))))
  (define fib (lambda (n) ((make-fib make-fib) n)))
  (print (fib 12))
  (print (+ (fib 6) 1)))))
