#!/bin/bash
# Oracle solution for item-058-main.
set -e
TARGET=/app/arithmetic.v

cat > "$TARGET" <<'EOF'
(* Completed proofs for item-058-main. *)

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

Theorem add_comm : forall n m : nat, n + m = m + n.
Proof.
  induction n as [ | n' IH].
  - intro m. simpl. rewrite plus_n_O. reflexivity.
  - intro m. simpl. rewrite plus_n_Sm. rewrite IH. reflexivity.
Qed.
EOF

coqc "$TARGET"
echo "coqc passed"