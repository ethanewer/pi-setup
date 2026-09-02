# Topaz Marsh — exact weighted Max-SAT for sensor pin mapping

The Topaz Marsh ecology station maps sensor pins with a weighted
constraint-satisfaction model. You must build an **exact** weighted Max-SAT
solver and run it on the provided instance. "Exact" means the true global
optimum — a greedy, local-search, or any other heuristic answer is a wrong
answer and will not match the reference optimum.

## Provided data (read-only; do not modify)

- `/app/instances/visible.wcnf` — the visible weighted CNF instance.

`scipy` (version 1.13.1, includes `scipy.optimize.milp` backed by HiGHS) is
installed in this container; you may also implement your own complete
branch-and-bound. No other packages and no network are available.

## Deliverables (both required)

1. `/app/wmaxsat.py` — the exact solver with exactly this CLI:
   ```
   python3 /app/wmaxsat.py <instance.wcnf> <out.json>
   ```
2. `/app/answer.json` — the result of running your solver on the visible
   instance:
   ```
   python3 /app/wmaxsat.py /app/instances/visible.wcnf /app/answer.json
   ```

## Input format (DIMACS-style WCNF)

The instance file contains one directive per line:

- `c <text>` — a comment line; ignore it.
- `p wcnf <nvars> <nclauses>` — the problem line. Boolean variables are
  numbered `1..nvars`.
- `h <lit> <lit> ... 0` — a **hard** clause (the literal `h` marks it).
- `<w> <lit> <lit> ... 0` — a **soft** clause with positive integer weight
  `<w>`.

A **literal** is a non-zero integer: positive `k` means variable `k` must be
**true** to satisfy that occurrence, negative `-k` means variable `k` must be
**false**. A clause is **satisfied** when at least one of its literals takes
its sign-matched truth value. Each clause line ends with a terminating `0`
(the `0` is not a literal). A clause may contain a repeated or directly
contradictory pair of literals (e.g. `7 5 -5 0` is a tautology: it is
satisfied under every assignment because literals `5` and `-5` cannot both be
false).

## Required semantics

Among all `2^nvars` assignments that satisfy **every hard clause**, find one
that **maximises the sum of weights of satisfied soft clauses**. That maximum
sum is the optimum.

Write `<out.json>` as exactly one of:

```json
{"status": "OPTIMAL", "objective": <integer optimum>}
```

or, when the hard clauses are jointly unsatisfiable (no assignment satisfies
all of them):

```json
{"status": "HARD_UNSAT"}
```

`objective` must be the exact global optimum (an integer). Note that soft
clauses that directly contradict a hard clause can never be satisfied and
contribute 0; tautological soft clauses are always satisfied and always
contribute their full weight.

## Edge cases the grader probes with hidden instances

- A **large satisfiable** instance (dozens of variables, well over a hundred
  soft clauses with mixed weights) where the optimum is strictly below the
  total soft weight.
- An instance whose **hard clauses are jointly contradictory** (e.g. unit
  clauses `x1` and `-x1`) — the answer must be `HARD_UNSAT` regardless of the
  soft clauses.
- An instance where unit hard clauses **pin** variables, making some soft
  clauses permanently unsatisfiable.
- Tautological soft clauses (weight always earned) and unit soft clauses.
- Comment lines and blank-ish noise between clauses must be tolerated.

## Constraints

- The grader runs `/app/wmaxsat.py` **unchanged** on hidden instances in the
  same format — do not hard-code the visible instance.
- The solver must be complete/exact. Verifier answers are compared to a
  reference optimum computed by an independent exact method, so a heuristic
  (walksat-style) value will not match.
- Do not modify `/app/instances/visible.wcnf`.
- Deterministic behaviour; runtime per instance must stay within 2 minutes.
