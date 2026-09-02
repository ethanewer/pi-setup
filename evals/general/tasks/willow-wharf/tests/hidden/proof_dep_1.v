Require Import Arith.
Require Import proof.

(* Corollary of the consultant's completed module: the two accumulations agree
   in the opposite direction too (checks names/types/linkage of the compiled
   proof.vo). *)
Theorem sumdown_eq_sumup : forall n : nat, sumdown n = sumup n.
Proof.
  intros n.
  symmetry.
  apply sumup_eq_sumdown.
Qed.