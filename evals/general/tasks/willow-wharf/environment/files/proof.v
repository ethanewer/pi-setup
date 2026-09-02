(* =========================================================================
   Willow Wharf - proof module
   -------------------------------------------------------------------------
   Build against the installed Coq:  coqc proof.v
   The compiled module must expose both fixpoints below and one theorem
   `sumup_eq_sumdown`.  This file currently contains an unfinished proof:
   it still carries an `admit` and does NOT qualify.  Complete the induction.
   ========================================================================= *)

Require Import Arith Lia.

(* Sum of the first n non-negative naturals, "up" accumulation. *)
Fixpoint sumup (n : nat) : nat :=
  match n with
  | O   => O
  | S k => sumup k + S k
  end.

(* The same summation accumulated "down", used by the report's appendix. *)
Fixpoint sumdown (n : nat) : nat :=
  match n with
  | O   => O
  | S k => S k + sumdown k
  end.

Theorem sumup_eq_sumdown : forall n : nat, sumup n = sumdown n.
Proof.
  induction n as [ | n' IHn ].
  - (* n = 0:  sumup 0 = sumdown 0 *)
    admit.
  - (* n = S n': use IHn, simplify, and the commutativity of + *)
    admit.
Qed.