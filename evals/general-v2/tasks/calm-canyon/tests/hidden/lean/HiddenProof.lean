import Math.Sum

-- Hidden theorem injected by the verifier into the agent's lake project.
-- It compiles only if the project's manifest pulls the bundled math library
-- (Math.Sum) and that dependency actually resolves.

namespace Basin.Hidden

theorem double_half (a b : Nat) : Math.Sum.doubleSum a b = 2 * a + b :=
  Math.Sum.doubleSum_eq a b

theorem comm_hidden (a b : Nat) : a + b = b + a :=
  Math.Sum.add_comm_own a b

theorem square_pos_hidden (n : Nat) (hn : 0 < n) : 0 < n * n :=
  Math.Sum.sq_pos n hn

theorem square_42_hidden : 0 < 42 * 42 :=
  Math.Sum.sq_pos 42 (by decide)

end Basin.Hidden