(* Task: complete every proof below. This file must compile under:
       coqc /app/arithmetic_hard.v
   with no errors and no warnings that stop the build.

   RULES (non-negotiable):
     - Do NOT change any theorem name, statement, or declaration ordering.
     - Do NOT add ANY new top-level Lemma / Theorem / Fixpoint / Definition /
       Inductive / Axiom / Parameter declarations. Exactly these five
       declarations may exist in the file (the four lemmas below and the final
       Theorem).
     - Do NOT add Require Import lines (especially not Arith or Lia) and do NOT
       use Admitted, Admit, Axiom, Parameter, lia, or omega anywhere.
     - Reason purely by Peano induction on nat and by rewriting using exactly
       the lemmas you prove here. Prefer the smallest lemma sequence that gets
       each goal to close, and let the coqc checker drive your iteration.

   The final target theorem is deliberately not provable from a single lemma:
   you must combine commutativity and associativity in exactly two rewrite steps. *)

Lemma plus_n_O : forall n : nat, n + 0 = n.
Proof. Qed.

Lemma plus_n_Sm : forall n m : nat, n + S m = S (n + m).
Proof. Qed.

Lemma comm : forall n m : nat, n + m = m + n.
Proof. Qed.

Lemma plus_assoc : forall a b c : nat, (a + b) + c = a + (b + c).
Proof. Qed.

Theorem final_goal : forall x y z : nat, (x + y) + z = (y + z) + x.
Proof. Qed.