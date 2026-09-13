(declare-const x Bool)
(declare-const y (Seq Int))
(assert (= y (seq.extract (seq.++ (seq.++ (seq.unit (seq.len y)) (seq.unit (ite x 0 1))) (seq.++ (seq.unit 5) (seq.unit 6) (seq.unit 7))) 2 3)))
(check-sat)
