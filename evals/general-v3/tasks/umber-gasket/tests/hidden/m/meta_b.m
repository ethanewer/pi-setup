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

;; subject:  (if (< (* 3 4) (sq 5)) (+ 1 (sq 2)) (* 3 (twice 6)))
;;   3*4=12 ; sq5=25 ; 12<25 true -> 1+sq2(4) = 5
(print (value (quote
  (if (< (* 3 4) (sq 5)) (+ 1 (sq 2)) (* 3 (twice 6))))))