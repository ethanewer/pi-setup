namespace Math.Sum

/-- Twice-first-plus-second. A stable helper kept in the bundled math library. -/
def doubleSum (a b : Nat) : Nat := a + a + b

theorem doubleSum_eq (a b : Nat) : doubleSum a b = 2 * a + b := by
  rw [doubleSum]
  omega

theorem add_comm_own (a b : Nat) : a + b = b + a := by
  omega

theorem sq_pos (a : Nat) (h : 0 < a) : 0 < a * a := by
  exact Nat.mul_pos h h

end Math.Sum