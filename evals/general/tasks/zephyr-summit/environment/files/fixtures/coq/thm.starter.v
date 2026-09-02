(*** Zephyr Summit proof module -- starter.
    Complete every placeholder below (each `Admitted` / `(* TODO *)` marker) with a
    real, closing tactic script so that the whole file compiles with `coqc` and
    contains NO `Admitted`, `admit`, `Axiom`, or `TODO`. You may add helper lemmas
    but not change any statement. ***)

Require Import Coq.Lists.List Coq.Arith.PeanoNat Lia.
Import ListNotations.
Open Scope nat_scope.

(* --- complete reference examples (do not touch) --- *)

Fixpoint lsum (s : list nat) : nat :=
  match s with [] => 0 | n :: t => n + lsum t end.

Lemma lsum_app : forall l m : list nat,
    lsum (l ++ m) = lsum l + lsum m.
Proof.
  intros. induction l as [|a t IH]; simpl.
  - lia.
  - rewrite IH. lia.
Qed.

(* --- placeholders to complete --- *)

Fixpoint rep (x n : nat) : list nat :=
  match n with 0 => [] | S k => x :: rep x k end.

Lemma lsum_rep : forall n x : nat, lsum (rep x n) = n * x.
(* TODO: complete this proof (induction on n). *)
Admitted.

Fixpoint revA {A : Type} (l : list A) : list A :=
  match l with [] => [] | h :: t => revA t ++ [h] end.

Lemma revA_app : forall (A : Type) (l m : list A),
    revA (l ++ m) = revA m ++ revA l.
(* TODO: complete this proof (induction on l; needs app_nil_r and app_assoc). *)
Admitted.

Lemma revA_length : forall (A : Type) (l : list A),
    length (revA l) = length l.
(* TODO: complete this proof (induction on l; uses app_length). *)
Admitted.

Fixpoint sum_upto (n : nat) : nat :=
  match n with 0 => 0 | S k => sum_upto k + n end.

Lemma gauss : forall n : nat, sum_upto n * 2 = n * (n + 1).
(* TODO: complete this proof (hardest one; induction on n plus polynomial
        arithmetic -- lia alone is not enough once products of n appear). *)
Admitted.

(* --- complete reference example (do not touch) --- *)

Theorem summit : forall l m : list nat,
    lsum (l ++ m) = lsum m + lsum l.
Proof.
  intros. rewrite lsum_app. lia.
Qed.
