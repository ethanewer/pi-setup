# An unconstrained linear program must not crash

## Situation

`/app/src` is a git checkout of the sympy project
(`https://github.com/sympy/sympy`), detached at upstream commit
`6a968f7201e5d9187b50dbdc2cc66b17594a59ac`, and installed from that tree in
editable (development) mode, so the code you import is exactly the checked-out
source. Python 3.12, pytest and hypothesis are installed, and the project's
own test configuration is in `/app/src/pyproject.toml`. There is **no
network** at trial time: everything you need is already in the image; `pip`
and `git fetch` will not work.

The linear-programming helpers live in the solver module at this commit
(they are not yet exported at the package top level). `linprog(c, A=None,
b=None, A_eq=None, b_eq=None, bounds=None)` minimises `c*x` subject to
`A*x <= b` and `A_eq*x = b_eq`, with variables nonnegative by default:

```
>>> from sympy.solvers.simplex import linprog
>>> linprog([1], [-1], [-1])     # minimise x1 with -x1 <= -1
(1, [1])
```

## The bug

Calling `linprog` with only the cost row and **none** of the constraint
matrices crashes with a misleading error deep inside the solver instead of
solving the problem:

```
$ python3 /app/probe_linprog.py
== linprog with only the cost row, no constraints ==
linprog([1])   -> ValueError: must give A and B
linprog([1, 1]) -> ValueError: must give A and B
linprog([-1])  -> ValueError: must give A and B
```

These calls should all work. With no constraints every variable is simply
kept at its lower bound (0 by default), so:

- `linprog([1])` must return `(0, [0])` -- cost 0 at `x = [0]`;
- `linprog([1, 1])` must return `(0, [0, 0])`;
- `linprog([-1])` must raise `UnboundedLPError` (minimising `-x` over
  `x >= 0` has no lower bound), not crash with a `ValueError`.

Passing the default bounds explicitly (`bounds=(0, None)`) must behave
identically: `linprog([1], bounds=(0, None)) == (0, [0])` and
`linprog([-1], bounds=(0, None))` must raise `UnboundedLPError`.

## What you need to do

Find the root cause in the checked-out tree and fix it in place so the
unconstrained cases above behave as specified, **without changing any
behaviour of constrained problems**. The constrained example above
(`linprog([1], [-1], [-1]) == (1, [1])`) must keep working exactly as it does
now.

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest sympy/solvers/tests/test_simplex.py -q -p no:cacheprovider
```

The whole existing test file of the simplex module is green at the pinned
commit; keep it that way. Add your own tests if that helps you verify (for
example other cost rows and larger unconstrained problems), but the verdict on
your fix is made by the verifier, which runs checks of its own.

## Constraints

- Network is unavailable; everything needed is installed already.
- The checkout at `/app/src` is the deliverable. Change only the minimal
  source surface the fix requires, in place. Do not rewrite history, add
  remotes, fetch, or change any tracked test, build or configuration file.
- Files under `/opt/golden`, `/tests` and `/solution` are harness-owned; do
  not touch them.
- The verifier also asserts that the tree is still at the pinned commit, that
  the upstream fix commit is not reachable from your clone, and that no
  tracked files other than the one your fix needs were modified.

## What the verifier checks

1. The tree is still at commit `6a968f7201e5d9187b50dbdc2cc66b17594a59ac` and
   the only modified tracked file is the one that implements the fix.
2. The project's upstream regression test for this behaviour passes.
3. The project's own existing simplex-module tests still pass.
4. Hidden cases over inputs the upstream regression test does not use pass:
   explicit empty constraint matrices (`A=[], b=[]`, `A_eq=[], b_eq=[]`,
   zero-row `Matrix` objects), larger / zero-entry / rational / floating-point
   cost rows, and default-bounds forms over more than one variable, including
   their unbounded (`UnboundedLPError`) counterparts.

Deliverable: the repaired `/app/src` tree.