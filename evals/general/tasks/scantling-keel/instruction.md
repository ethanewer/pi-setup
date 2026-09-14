# scantling-keel

You are working inside a real open-source codebase: **SymPy** — the Python
computer algebra library (`sympy/sympy`) — checked out at a pinned historical
commit in `/app/src`. There is a bug in its system-of-equations solver. Your
job is to find it, fix it in the working tree, and prove the fix with your own
reproduction and the project's own test tooling. You are deliberately **not**
told which file or function to change: localising the bug is part of the task.

## Environment

- Python 3.12.13. SymPy is installed **editable** from `/app/src`, so
  `import sympy` resolves to that tree and your edits to it take effect
  immediately (a fresh Python process each time: `python3 -c "..."`).
  `mpmath==1.3.0`, `pytest==9.1.1` and `hypothesis==6.168.0` are installed.
- The tree `/app/src` is writable by you, but **do not commit, fetch, push,
  rebase or otherwise modify `.git`** — the working tree is detached at the
  pinned commit and must stay there. Apart from the source file(s) where the
  bug lives, the tree must end up byte-identical to that commit: no new
  files, no deleted files, no edits to tests, packaging or metadata.
- **There is no network** in this container. Everything you need is baked in.
- `cpus = 1`: one vCPU. Importing sympy takes 1–2 seconds; a single pytest
  node a few more. Prefer many small `python3 -c` probes over long processes.
- A second, pristine, unmodified checkout of the same pinned commit lives at
  `/opt/prefix-sympy`. You may read it; do not modify it. The container's own
  regression test for this bug is baked in at `/opt/golden/`.

## The bug (user-visible symptom)

`sympy.nonlinsolve` solves systems of equations and returns the solution set.
When **one of the equations** in a system involves the `sign()` function —
the equation `sign(x) - 1` encodes the constraint `x > 0` — solving a
**system** that contains it can blow up with a low-level arithmetic crash
instead of returning an answer. The crash is not a deliberate "I cannot solve
this" signal; it is a raw exception escaping from deep inside SymPy's own
arithmetic, looking like:

```
TypeError: unsupported operand type(s) for /: 'Integer' and 'Interval'
```

Root cause, as an expert would describe it: the sub-solver reduces the
sign equation to an *interval* of `x` values — `sign(x) - 1 = 0` reduces to
the open interval `(0, oo)` — and the system-solver then keeps using that
interval as if it were a single value, dividing other expressions by it and
so on, until the arithmetic blows up. A lone sign equation is not crashed
on, but the value it returns is also not a proper answer: it is a
`FiniteSet` that still contains an unsolved evaluation placeholder
(a `ConditionSet`), i.e. a result that cannot be evaluated further.

Correct behaviour — this is the contract the verifier enforces, and the
contract your own reproduction must check:

- A call like `nonlinsolve([sign(x) - 1, x*y - 4], [x, y])` or
  `nonlinsolve([sign(x) - 1, x - y], [x, y])` must **not** crash with a
  `TypeError` or any other low-level arithmetic error. The solver may
  legitimately decide such an input is beyond its capability; when it does,
  that decision must surface as a solver-level `NotImplementedError` whose
  message explains what it cannot handle and names the offending solution
  type (the word `Interval` appears in the message).
- `nonlinsolve([sign(x) - 1], [x])` must return a `FiniteSet`.

## Your job

1. **Write a failing reproduction first.** Before you change any source code,
   write `/app/repro.py` — your own minimal reproduction of the symptom. Its
   exact contract:

   - It must let the caller point it at an alternate sympy checkout: if the
     environment variable `SYMPY_SRC` is set, the script must
     `sys.path.insert(1, os.path.abspath(SYMPY_SRC))` **before** importing
     sympy; when it is unset, it imports the installed (editable) sympy from
     `/app/src`. This is how the verifier runs the same script against the
     pre-fix reference tree.
   - Using `x, y = symbols('x y')` it must perform and report three checks:

       `a)` a system pairing the sign equation with a second equation —
            `nonlinsolve([sign(x) - 1, x*y - 4], [x, y])`
       `b)` the same sign equation with a different companion —
            `nonlinsolve([sign(x) - 1, x - y], [x, y])`
       `c)` the lone sign equation — `nonlinsolve([sign(x) - 1], [x])`

   - For (a) and (b) it must fail unless the call raises
     `NotImplementedError` with a message containing the word `Interval`
     (your script should report the actual outcome: the exception type, or
     the returned value if none was raised). For (c) it must fail unless the
     result is a `FiniteSet`.
   - It prints what it observes — one line per check — and **exits 0 if and
     only if all three checks pass**, non-zero otherwise.
   - It must work no matter what the current working directory is, must not
     write any file, and must not touch `/app/src`.

   On the **unfixed** tree this script must fail (checks (a) and (b) crash
   with the `TypeError`). Confirm that now, before fixing anything: e.g.
   `python3 /app/repro.py`, and also `SYMPY_SRC=/opt/prefix-sympy
   python3 /app/repro.py` (the verifier will use the latter as its pre-fix
   direction). Then keep the script as your regression harness while you fix.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.py` exits 0, and so that the solver no longer turns any
   related input into a low-level arithmetic crash. Handle the defect where
   it happens, in the solver's own flow — do not special-case `sign`
   itself, and do not paper over the symptom with a wrapper around
   `nonlinsolve`. SymPy prints a "DO *NOT* COMMIT!" notice at pytest
   startup; it is harmless.

3. **Break nothing else.** The solver's existing behaviour must keep working:
   systems whose equations are polynomial, radical, or involve `Abs`
   (which already raise a clear solver-level error in this code), and the
   lone-sign equation's `FiniteSet` contract. The project's own regression
   test for this bug will be planted into the tree by the verifier and must
   pass, along with a selection of pre-existing tests.

4. **Write `/app/summary.md`** — a non-empty write-up: what the symptom was,
   what you changed and why, and how you verified the fix (commands and their
   observed output).

## Recommended working loop

1. Probe first, with short one-liners of your own: try a system that pairs
   a sign equation with a second equation, a lone sign equation, and a few
   further variations of your own choosing (a different sign coefficient, the
   sign on the other symbol of the system, a different companion equation).
   Observe which of your probes crash, which raise an error, and what the
   lone sign equation actually returns.
2. Localise: read the solver code to trace how a first equation's solution
   for a symbol flows into the computation for the next equation, where an
   interval-shaped solution would be combined and later divided, and where
   errors of the "clear cannot-handle" kind are supposed to be raised and
   caught in that flow. Understand *why* your crashing inputs reach the raw
   arithmetic error while the existing `Abs` cases reach a clean
   solver-level error.
3. Fix, then run `/app/repro.py` — it must exit 0 now, on both the editable
   install and (still failing) on `/opt/prefix-sympy`.
4. Prove nothing else broke with quick targeted pytest nodes from
   `/app/src/sympy/solvers/tests/test_solveset.py`, e.g. the pre-existing
   nonlinsolve tests: `test_nonlinsolve_basic`, `test_nonlinsolve_abs`,
   `test_raise_exception_nonlinsolve`. Run them one node at a time, e.g.
   `cd /app/src && python3 -m pytest
   'sympy/solvers/tests/test_solveset.py::test_nonlinsolve_abs'
   -p no:cacheprovider`.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.py` — your failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (mounted at `/tests`) will, on your final tree:

- assert `HEAD` is still the pinned parent commit and that the upstream fix
  commit is **not** reachable from this clone's object store;
- diff the whole working tree byte-for-byte against the pristine pre-fix
  checkout at `/opt/prefix-sympy`, allowing **only the source file(s) where
  the bug lives** to differ — any added, deleted, renamed or edited file
  elsewhere fails the task;
- verify the trust anchors recorded at image build time (sha256 of the
  golden test, of the pre-fix solver module, and of the interpreter/pytest)
  were not substituted;
- require `/app/repro.py` and `/app/summary.md` to exist and behave per
  their contracts: `/app/repro.py` must exit 0 against the repaired tree and
  must fail against the pre-fix reference tree at `/opt/prefix-sympy`;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`) over the tree's copy of the solver test file, run
  it against the repaired tree and require it to pass — note that the same
  test, run against the pre-fix reference tree, must fail, which is part of
  why the reproduction you write must be genuine;
- run a selection of the project's existing nonlinsolve tests (a few nodes;
  e.g. `test_nonlinsolve_basic`, `test_nonlinsolve_abs`,
  `test_nonlinsolve_positive_dimensional`, `test_nonlinsolve_polysys`,
  `test_nonlinsolve_using_substitution`, `test_nonlinsolve_complex`,
  `test_nonlinsolve_radical`, `test_raise_exception_nonlinsolve`) and
  require them to stay green;
- run authored hidden cases that reach the same solver code path from inputs
  the upstream regression test does not use, and require them to behave like
  the contract in this file (solver-level `NotImplementedError` naming the
  solution type, never a raw arithmetic crash).

Reward is binary: 1 if and only if all of the above hold, otherwise 0.