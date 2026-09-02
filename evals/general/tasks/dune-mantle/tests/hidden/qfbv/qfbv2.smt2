(set-logic QF_BV)
(declare-fun p () (_ BitVec 16))
(assert (= (bvand p #x00FF) #x0100))
(check-sat)
