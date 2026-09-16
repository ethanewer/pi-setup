(declare-const x Bool)
(declare-const y (Seq Int))
(assert (= y (seq.extract (seq.++ (seq.++ (seq.unit (ite x -5 2)) (seq.unit (seq.len y))) (seq.++ (seq.unit 9) (seq.unit 4))) 2 2)))
(check-sat)
