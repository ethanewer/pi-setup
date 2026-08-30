; meta_a.m -- self-interpretation subject without `if`.
; meta_b.m -- a second self-interpretation subject that also exercises `if`.
(define cadr  (lambda (x) (car (cdr x))))
(define caddr (lambda (x) (car (cdr (cdr x)))))
(define cadddr (lambda (x) (car (cdr (cdr (cdr x))))))

(define cond2
  (lambda (p a b)
    (if (eq? p '<) (< a b)
      (if (eq? p '=) (= a b)
        (if (eq? p '>) (> a b) #f)))))

(define value
  (lambda (e)
    (if (number? e) e (exec e))))

(define exec
  (lambda (e)
    (if (eq? (car e) '+)
        (+ (value (cadr e)) (value (caddr e)))
      (if (eq? (car e) '-)
          (- (value (cadr e)) (value (caddr e)))
        (if (eq? (car e) '*)
            (* (value (cadr e)) (value (caddr e)))
          (if (eq? (car e) 'sq)
              (* (value (cadr e)) (value (cadr e)))
            (if (eq? (car e) 'twice)
                (* 2 (value (cadr e)))
              (if (eq? (car e) 'if)
                  (if (cond2 (car (cadr e))
                             (value (cadr (cadr e)))
                             (value (caddr (cadr e))))
                      (value (caddr e))
                      (value (cadddr e)))
                -1))))))))

;;; subject:  (+ (* 2 (sq 3)) (- (* 4 5) 6))  -> 2*9 + (20-6) = 32
(print (value (quote
  (+ (* 2 (sq 3)) (- (* 4 5) 6)))))