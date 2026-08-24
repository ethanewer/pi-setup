# Verify a logical formula

Consider the propositional logic formula `F` over the three boolean variables `p`, `q`, `r`:

```
F = ( (p -> q) and (q -> r) ) -> (p -> r)
```

Here `->` is logical implication and `and` is logical conjunction.

Write a Python program `/app/formula_check.py` that performs an **exhaustive check** of `F` over **all 8 possible truth assignments** of `(p, q, r)`, and decides whether `F` evaluates to **True for every assignment** (i.e. whether it is a **tautology**).

Then write the single line verdict to `/app/verdict.txt`:

- if `F` is True for all 8 assignments: write exactly `tautology`
- otherwise: write exactly `nontheorem`

Run `/app/formula_check.py` so `/app/verdict.txt` exists. The verifier recomputes the same truth table from the formula above and checks your verdict matches.