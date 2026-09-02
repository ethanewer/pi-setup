; hidden unsat: x == 7 and x != 7 cannot both hold
(set-logic QF_BV)
(declare-const x (_ BitVec 8))
(assert (= x (_ bv7 8)))
(assert (not (= x (_ bv7 8))))
(check-sat)
