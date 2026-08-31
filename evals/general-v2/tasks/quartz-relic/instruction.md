# Author the `dotkit` package with a public scalar product

The repository in `/app` is a small numerical-tools repo. A former maintainer
left a working scalar-product implementation as a **loose module** at
`/app/dotlib.py`, but the team's published API is a **package** called
`dotkit` that must expose the scalar product directly from its root module.
Only an incomplete skeleton of that package exists.

## Environment

- Working directory: `/app`. Python 3.12 is available as `python3`.
- `/app/dotlib.py` — frozen legacy module with a reference `dot`
  implementation. **Do not modify it.**
- `/app/dotkit/` — the incomplete package skeleton (its `__init__.py` does
  not yet provide the public function).

## Deliverable

**`/app/dotkit`** — a self-contained, importable Python package.

The grader imports the package from a *fresh interpreter* with `/app` on the
module search path, and it must work:

```python
import dotkit
dotkit.dot(...)          # callable

from dotkit import dot   # must also work
```

### Self-containment (strictly enforced)

The grader copies **only the `/app/dotkit` directory** to an isolated
location that does **not** contain `/app/dotlib.py` or any other repo
module, and imports it from there. Therefore `dotkit` must be
self-contained:

- It must **not** import `dotlib`, nor any other module that lives directly
  under `/app` (outside the package).
- It may use additional modules *inside* the package (e.g.
  `dotkit/_core.py`) as long as the root module `dotkit/__init__.py` itself
  exposes `dot`.
- Standard library only; no third-party imports, no network.

### The `dot(a, b)` contract

`dot` computes the scalar (dot) product of two numeric sequences:

- `a` and `b` are sequences (lists or tuples) of numbers (ints and/or
  floats), of equal length.
- Returns the sum of the element-wise products: `a[0]*b[0] + a[1]*b[1] + ...`.
- If the two sequences have **different lengths**, it must raise
  `ValueError`.
- If both sequences are **empty**, it returns `0`.
- It must accept both lists and tuples, and mixtures of ints and floats.
- It must **not** mutate its inputs (the caller's sequences must be
  unchanged after the call).
- Integer-only inputs should produce an exact integer result.

### Hidden probes the grader runs

The grader executes your delivered `/app/dotkit` package on hidden inputs
that follow the contract above — including, at least: integer inputs,
fractional inputs, negative values, single-element inputs, tuple inputs,
mixed int/float inputs, empty sequences, length-mismatched sequences (must
raise `ValueError`), and an input-immutability check. Do not hard-code any
specific values.

## Constraints

- Do not modify `/app/dotlib.py` (it is checked byte-for-byte).
- Do not add anything outside `/app` (and inside `/app`, only the `dotkit`
  package is graded).
- No network access; standard library only.
