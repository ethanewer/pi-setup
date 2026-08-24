You are writing code in **Gallina**, the logical specification language used by the Coq proof assistant.

Write `/app/gallina.v`, a syntactically valid Gallina file that defines a recursive function named `double` over type `nat`. It must:

1. Declare a `Fixpoint` named `double` with the type signature `(n : nat) : nat`.
2. Use structural recursion via a `match n with ... end` expression.
3. Have a base case matching natural `0` that returns `0`.
4. Have a recursive case matching `S k` (the successor of a natural `k`) that returns the successor-of-successor of `double k`, i.e.:
   ```
   | S k => S (S (double k))
   ```
   (Adding `2` for the current successor-level; base case covers `0`.)
5. Terminate the Fixpoint with a period on its own final line.

A correct file looks structurally like:
```
Fixpoint double (n : nat) : nat :=
  match n with
  | 0 => 0
  | S k => S (S (double k))
  end.
```

Produce `/app/gallina.v` with your definition. Do not include anything that breaks Gallina syntax (e.g., unbalanced parentheses).