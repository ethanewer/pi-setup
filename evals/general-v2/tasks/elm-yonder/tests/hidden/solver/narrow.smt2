; hidden sat: a narrow 4-bit range has a satisfying assignment x*x == 1
(set-logic QF_BV)
(declare-const x (_ BitVec 4))
(assert (= (bvmul x x) (_ bv1 4)))
(check-sat)