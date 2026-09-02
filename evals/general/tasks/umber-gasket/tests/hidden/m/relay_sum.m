; relay_sum.m -- reads integers from its relayed stdin until EOF and prints the
; running sum. Exercises the evaluator's (read-int)/(eof?) input relay.
(define reader
  (lambda (acc)
    (if (eof?) acc
        (reader (+ acc (read-int))))))
(print (reader 0))