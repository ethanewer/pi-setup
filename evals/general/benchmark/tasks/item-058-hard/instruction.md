# Hard Arithmetic Theorems in Coq

A machine-checked proof file is at `/app/arithmetic_hard.v`. It is a Coq /
Gallina script about the natural numbers (`nat`, `S`, `+`). It contains five
theorems whose proofs are currently empty placeholders:

```coq
Lemma plus_n_O  : forall n : nat, n + 0 = n.
Lemma plus_n_Sm : forall n m : nat, n + S m = S (n + m).
Lemma comm      : forall n m : nat, n + m = m + n.
Lemma plus_assoc: forall a b c : nat, (a + b) + c = a + (b + c).
Theorem final_goal : forall x y z : nat, (x + y) + z = (y + z) + x.
```

## Your Task

Fill in the **body** of each `Proof. ... Qed.` block with a genuine, correct
Coq proof, then make the whole file compile cleanly:

```
coqc /app/arithmetic_hard.v
```

`coqc` must print no errors and exit 0 when you are done. Keep the corrected
file at `/app/arithmetic_hard.v`.

## Structural rules (the verifier enforces these hard)

1. Do not change any theorem name, statement, or the ordering of the five
   declarations.
2. Do not add **any** additional top-level declaration. The file may contain
   exactly these five top-level `Lemma`/`Theorem` names:
   `plus_n_O`, `plus_n_Sm`, `comm`, `plus_assoc`, `final_goal`.
3. Do not add `Require Import` lines (in particular not `Arith` or `Lia`) and
   never use `Admitted`, `Admit`, `Axiom`, `Parameter`, `lia`, or `omega`.
4. Work purely with Peano induction, `simpl`, `rewrite` (using the lemmas you
   proved in this very file), and `reflexivity`. Prefer the **smallest lemma
   sequence** that closes each goal.

## Strategy hints (the "smallest sequence" style that works)

- `plus_n_O` and `plus_n_Sm` follow by plain induction on `n`; after each
  case, `simpl` unfolds `+` and closes by `reflexivity`.
- `comm` needs induction on `n`, using `plus_n_O` and `plus_n_Sm` inside the
  two step cases, then `reflexivity`.
- `plus_assoc` follows by induction on `a`.
- `final_goal` is the subtle one and is **not** solvable by a single lemma
  application. The robust route is **induction on `x`**:
  - base: simplify both sides to a syntactic identity and close;
  - step: after `simpl` the goal becomes `S ((x' + y) + z) = S ((y + z) + x')`
    where `x'` is the induction predecessor; a single `rewrite` of the
    induction hypothesis only hits that one occurrence, then `reflexivity`
    closes.
  Be aware that Coq's `rewrite` rewrites a lemma's left-hand side *wherever it
  matches* in the goal: a careless `rewrite comm` will also swap an
  already-commuted subterm on the other side and can spin forever. If you try
  the associativity+commutativity chaining route, check after each step which
  occurrence actually got rewritten (coqc prints the resulting goal) and
  re-aim, or fall back to the induction route above.

## Iteration method

Run `coqc /app/arithmetic_hard.v`, read the first error message, apply the
smallest fix, and re-run. Repeat until the file compiles with no errors.
The proof checker is your oracle: each error tells you exactly which goal is
still open, so fix only that step and re-check.

## Success criteria

A verifier checks that `/app/arithmetic_hard.v` (a) compiles cleanly under
`coqc`; (b) contains none of `Require`, `Admitted`, `Admit`, `Axiom`,
`Parameter`, `lia`, `omega` in its code (comments are ignored); and (c)
declares exactly the five theorem names above in exactly the given order, none
of them `Admitted`.