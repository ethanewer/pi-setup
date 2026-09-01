# Farehaven toll-plate arithmetic engine

The **Farehaven toll office** runs a plate-number game: given a pool of
**allowed numbers** and a **target toll**, drivers submit an arithmetic
expression. An expression is **valid** only if every number used comes from
the allowed pool and **no number is used more times than it appears in the
pool** (one use per occurrence). You must write a solver that finds a valid
expression reaching the target — or proves none exists.

You work in `/app`. The fixture `/app/config.json` is already on disk.
**Do not modify `/app/config.json`**, and never read or touch anything under
`/tests` or `/solution`. The solver is re-run on **hidden** configs at verify
time, so it must be generic.

## Deliverables

1. **`/app/solver.py`** — an executable, generic Python program:

   ```
   python3 /app/solver.py <config.json> <outdir>
   ```

   - `<config.json>` is a JSON object: `{"allowed": [...integers, may repeat...], "target": <integer>}`.
     Do **not** assume a fixed config path.
   - Create `<outdir>` if it does not exist.
   - On **every** run it must write exactly one file `<outdir>/expression.txt`
     containing a **single line**:
     - either an arithmetic expression (see validity rules), or
     - the exact token `IMPOSSIBLE` (no expression exists).

2. **`/app/expression.txt`** — the result your solver produces for the shipped
   config:

   ```
   python3 /app/solver.py /app/config.json /app
   ```

## Expression validity rules (enforced on every hidden case)

- Only the operators `+`, `-`, `*` with standard precedence; parentheses are
  allowed and may be redundant.
- Every integer literal in the expression must be a value from `allowed`.
- **One use per occurrence**: a number may not appear in the expression more
  times than it appears in `allowed`. (If `allowed` is `[2, 2, 5]`, the
  literal `2` may appear at most twice.) A literal not in `allowed` at all is
  invalid.
- Using **fewer** numbers than the pool size is allowed (subsets are fine);
  using none at all is not (an empty expression is invalid).
- The expression must evaluate to **exactly** `target` with ordinary integer
  arithmetic (unary minus is allowed, e.g. `-(3)` or `-3` if `3` is allowed).
- Numbers with leading zeros (e.g. `04`) are invalid.

If no valid expression exists, `IMPOSSIBLE` must be written — a wrong or
invented expression fails; so does writing `IMPOSSIBLE` when a valid
expression exists.

## Edge cases the grader probes

- Configs whose solution **uses only a subset** of the pool.
- Configs with **duplicate values** in `allowed` (each occurrence usable once).
- **Negative targets** requiring subtraction (or unary minus).
- Configs where **no** valid expression exists (`IMPOSSIBLE`).
- Single-number pools (the expression may be just the number itself, if it
  equals the target).

## Constraints

- Standard library only; no network access; deterministic output.
- The verifier runs `/app/solver.py` **unchanged** on hidden configs and
  validates `expression.txt` with its own independent parser/evaluator.
