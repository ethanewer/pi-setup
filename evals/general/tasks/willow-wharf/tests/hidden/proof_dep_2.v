Require Import Arith Lia.
Require Import proof.

(* A second dependent goal built from the consultant's theorem: after one
   unrolling and Young's commutativity, the compiled equality closes it. *)
Theorem sumup_iter : forall n : nat, sumup (S n) = S n + sumdown n.
Proof.
  intros n.
  simpl.
  rewrite sumup_eq_sumdown.
  lia.
Qed.