# Wire up the `dotkit` public API in the package root

You are finishing a small Python package in **`/app/pkg`** (a PEP 621 project
with a `src` layout). The package skeleton, metadata, and documentation are
already in place, but the public API is missing: the root module
`src/dotkit/__init__.py` is an empty stub, and the only scalar-product code in
the package is a naive legacy helper `inner()` in `src/dotkit/vector.py` that
does **not** follow the public contract (it silently truncates mismatched
inputs via `zip`, never raises on non-numeric elements, and lives in the wrong
module).

## Your job

Implement the public function **`dot_product(a, b)` directly in
`/app/pkg/src/dotkit/__init__.py`**, following the contract in
`/app/pkg/README.md` exactly. The README is the specification; the hidden
verifier enforces it point by point. Highlights (full details in the README):

- `dot_product` computes the scalar (dot) product of two numeric sequences.
- Sequences may be lists, tuples, ranges, or any other iterable of
  `int`/`float` values (booleans count as ints).
- If every element of both inputs is an `int`, the result is an `int`; if any
  element is a `float`, the result is a `float`. Two empty sequences give `0`.
- Different lengths raise `ValueError` (lengths compared up front, so this
  also holds for one-shot iterators).
- Non-numeric elements (e.g. `str`, `None`, `list`) raise `TypeError`.
- The inputs must not be mutated.
- The function must be **defined in the root module itself**: after
  `import dotkit`, `dotkit.dot_product.__module__` must equal `"dotkit"`.
  Re-exporting `inner` (or anything else) from `dotkit.vector` does not
  satisfy the contract.

The old import path `from dotkit.vector import inner` keeps working for
legacy users — leave `vector.py` untouched.

## Deliverable

1. `/app/pkg/src/dotkit/__init__.py` — the completed root module.

## Rules

- **Do not modify** `pyproject.toml`, `README.md`, or
  `src/dotkit/vector.py`; they must stay byte-identical. The verifier checks
  their hashes.
- Do not touch anything outside `/app`.
- The package must remain installable offline; the verifier checks the API
  both from the source tree and from a fresh offline install:
  `python3 -m pip install --no-build-isolation --no-deps --target <dir> /app/pkg`
  (no network is available at verify time).
- Standard library only; no third-party dependencies.

The verifier imports `dotkit` from both locations and runs it against the
visible case below plus hidden edge cases (empty inputs, single elements,
mismatched lengths, non-numeric elements, tuples, generators, large ints,
float precision).

## Visible sanity checks

```bash
cd /tmp && python3 -c "
import sys; sys.path.insert(0, '/app/pkg/src')
from dotkit import dot_product
assert dot_product([1, 2, 3], [4, 5, 6]) == 32
assert dot_product((), ()) == 0
assert dot_product.__module__ == 'dotkit'
"
```
