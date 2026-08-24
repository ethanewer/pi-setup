#!/bin/bash
# Oracle solution for item-058-hard.
set -e
TARGET=/app/arithmetic_hard.v

cat > "$TARGET" <<'EOF'
(* Completed proofs for item-058-hard. *)

Lemma plus_n_O : forall n : nat, n + 0 = n.
Proof.
  induction n as [ | n' IH].
  - simpl. reflexivity.
  - simpl. rewrite IH. reflexivity.
Qed.

Lemma plus_n_Sm : forall n m : nat, n + S m = S (n + m).
Proof.
  induction n as [ | n' IH].
  - intro m. simpl. reflexivity.
  - intro m. simpl. rewrite IH. reflexivity.
Qed.

Lemma comm : forall n m : nat, n + m = m + n.
Proof.
  induction n as [ | n' IH].
  - intro m. simpl. rewrite plus_n_O. reflexivity.
  - intro m. simpl. rewrite plus_n_Sm. rewrite IH. reflexivity.
Qed.

Lemma plus_assoc : forall a b c : nat, (a + b) + c = a + (b + c).
Proof.
  induction a as [ | a' IH].
  - intros b c. simpl. reflexivity.
  - intros b c. simpl. rewrite IH. reflexivity.
Qed.

Theorem final_goal : forall x y z : nat, (x + y) + z = (y + z) + x.
Proof.
  intros x y z.
  rewrite plus_assoc.
  rewrite (comm (y + z) x).
  reflexivity.
Qed.
EOF

coqc "$TARGET"
echo "coqc passed"