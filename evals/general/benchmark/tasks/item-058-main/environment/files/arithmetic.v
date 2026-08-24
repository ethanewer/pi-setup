(* Task: complete the proofs below. Do NOT change any theorem statement.
   Do NOT add Require Imports, Axioms, or use "Admitted" anywhere.
   Use only Peano induction and the lemmas you actually prove.
   When done, the file (at /app/arithmetic.v) must compile under:
       coqc /app/arithmetic.v
   with no errors. Iterate with the checker: run coqc, read the error,
   fill in the smallest missing step, and re-run until it passes. *)

(* 1) For any natural number n, n + 0 = n. *)
Lemma plus_n_O : forall n : nat, n + 0 = n.
Proof. Qed.

(* 2) For any n, m, n + S m = S (n + m). *)
Lemma plus_n_Sm : forall n m : nat, n + S m = S (n + m).
Proof. Qed.

(* 3) Addition is commutative. Use the two lemmas above and induction on n. *)
Theorem add_comm : forall n m : nat, n + m = m + n.
Proof. Qed.