(* astral.v : explicitly-tactic proofs; no electronic search tactics. *)

Lemma plus_n_O : forall n : nat, n + 0 = n.
Proof.
  induction n as [| n IHn].
  - reflexivity.
  - simpl. rewrite IHn. reflexivity.
Qed.

Lemma plus_n_Sm : forall n m : nat, S (n + m) = n + S m.
Proof.
  induction n as [| n IHn]; intros m.
  - reflexivity.
  - simpl. rewrite <- IHn. reflexivity.
Qed.

Theorem add_comm : forall n m : nat, n + m = m + n.
Proof.
  induction n as [| n IHn]; intros m.
  - simpl. rewrite plus_n_O. reflexivity.
  - simpl. rewrite IHn. rewrite plus_n_Sm. reflexivity.
Qed.