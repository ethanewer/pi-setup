The following is a short Coq development. Read it, reason precisely about what it means, and answer the question below.

```coq
Definition succ (n : nat) : nat := n + 1.

Fixpoint pow2 (n : nat) : nat :=
  match n with
  | O    => 1
  | S m  => 2 * pow2 m
  end.

Theorem pow2_succ_pos : forall n : nat, pow2 (S n) > 0.
Proof.
  intros n. simpl. lia.
Qed.
```

Question: According to the `pow2` definition (where `O` is zero and `S m` is the successor of m), when `n = 2` the term `pow2 2` reduces (via `Definitional equality`) to a specific natural number. Compute `pow2 2`, then also compute `succ 3 = 4` in their usual arithmetic, and write:
- Line 1: the natural number that `pow2 2` reduces to,
- Line 2: the value of `succ (pow2 2)`.

Write the two results into `/app/answer.txt`, one integer per line.