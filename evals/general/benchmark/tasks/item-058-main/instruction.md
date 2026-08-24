# Proof a Small Arithmetic Lemma in Coq

A machine-checked proof file has been placed at `/app/arithmetic.v`. It is a
Coq/Gallina script about the natural numbers (`nat`, `S`, `+`). It currently
contains three declarations whose proofs are empty placeholders:

```coq
Lemma plus_n_O : forall n : nat, n + 0 = n.
Proof. Qed.

Lemma plus_n_Sm : forall n m : nat, n + S m = S (n + m).
Proof. Qed.

Theorem add_comm : forall n m : nat, n + m = m + n.
Proof. Qed.
```

## Your Task

Fill in the **body** of each `Proof. ... Qed.` block (between the `Proof.` and
the `Qed.`) so that every one of the three theorems is a genuine, correct Coq
proof based on mathematical induction on `nat`. Then make sure the whole file
compiles cleanly with the Coq command-line checker:

```
coqc /app/arithmetic.v
```

When you are finished, `coqc` must print **no errors** and exit successfully.
The completed file must remain at `/app/arithmetic.v`.

## Requirements and rules

- Do not change any theorem name or statement.
- Do not add `Require Import` lines (especially not `Arith` or `Lia`).
- Do not use `Admitted.`, `Admit`, `Axiom`, or `Parameter` to dodge the proofs.
- Do not open extra `Section`s or introduce shadowing.
- Use the machinery that is already there: mathematical **induction** on
  natural numbers, **rewriting** of the lemmas you prove, and reflexivity.
  Prefer the **smallest sequence of lemmas** that closes each goal.
- Let the checker drive your iteration: run `coqc`, read the first error, fix
  exactly that, and repeat until the file compiles cleanly.

## Success criteria

A verifier expects `/app/arithmetic.v` to:
1. compile cleanly under `coqc` (no errors, exit 0);
2. contain no `Require`, `Admitted`, `Admit`, `Axiom`, or `Parameter` tokens;
3. declare the three theorems `plus_n_O`, `plus_n_Sm`, `add_comm` in that
   order, each with a real proof (none of them `Admitted`).

You do not need to produce any other output. Just leave the corrected file on
disk.