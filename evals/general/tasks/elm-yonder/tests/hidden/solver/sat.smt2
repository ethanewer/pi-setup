; hidden sat: find an 8-bit x with x < 10
(set-logic QF_BV)
(declare-const x (_ BitVec 8))
(assert (bvult x (_ bv10 8)))
(check-sat)
