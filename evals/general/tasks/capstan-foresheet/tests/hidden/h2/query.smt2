; capstan-foresheet hidden case h2
; fp.rem with a subnormal divisor; half-precision operand pair not used by
; any visible case. Fully pinned operands: the query must be unsat.
(declare-const x (_ FloatingPoint 5 11))
(declare-const y (_ FloatingPoint 5 11))
(assert (= x ((_ to_fp 5 11) #b0101101100001001)))
(assert (= y ((_ to_fp 5 11) #b0000000000000011)))
(assert (not (= ((_ fp.to_ieee_bv 16) (fp.rem x y)) #x8001)))
(check-sat-using (then fpa2bv simplify bit-blast smt))
