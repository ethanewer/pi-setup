(declare-const x Bool)
(declare-const y (Seq Int))
(assert (= y (seq.extract (seq.++ (seq.++ (seq.unit (seq.len y)) (seq.unit (ite x -3 7))) (seq.++ (seq.unit 11) (seq.unit 0))) 2 2)))
(check-sat)
