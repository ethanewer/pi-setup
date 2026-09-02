; proof-of-work puzzle: find a 16-bit nonce x whose square,
; modulo 2^16, equals 0x8c5d.
(set-logic QF_BV)
(declare-const x (_ BitVec 16))
(assert (= (bvmul x x) #x8c5d))
(check-sat)
