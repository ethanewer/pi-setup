# dotkit

`dotkit` is a tiny vector-math toolkit. Its **public API lives in the package
root module** (`src/dotkit/__init__.py`); users import directly from the
package:

```python
from dotkit import dot_product
```

## The public function: `dot_product(a, b)`

`dot_product` computes the scalar (dot) product of two numeric sequences.

**Arguments.** `a` and `b` are sequences of numbers — lists or tuples whose
elements are instances of `int` or `float` (booleans count as ints). They may
also be any other iterable of numbers (e.g. a generator or a `range`).

**Result.** The sum of `a[i] * b[i]` over all positions, with these exact
typing rules:

- If **every** element of both sequences is an `int` (or `bool`), the result
  is an `int` (Python ints are unbounded; never overflow).
- If **any** element is a `float`, the result is a `float`.
- Two empty sequences give `0` (an `int`).
- A single-element pair gives the product of that element.

**Errors.**

- If the sequences have **different lengths**, raise `ValueError`. The lengths
  must be compared up front, so this holds even when the inputs are one-shot
  iterators.
- If any element is not an `int`/`float` (e.g. a `str`, `None`, a list),
  raise `TypeError`. The error must be raised regardless of position (even if
  a mismatch in length would also apply — either error is acceptable then, but
  a non-numeric element must never be silently multiplied).
- The inputs must not be mutated.

The function must be **defined in `src/dotkit/__init__.py` itself** — the
package root is the documented API surface, so
`dot_product.__module__ == "dotkit"` must hold. Merely re-exporting a helper
from a submodule (e.g. `vector.py`) does NOT satisfy the contract.

## Package layout (already correct — do not change)

```
pkg/
  pyproject.toml      # PEP 621 metadata, src layout
  README.md
  src/dotkit/
    __init__.py       # <- the public API goes here (currently a stub)
    vector.py         # legacy helper module, kept as-is
```

The package must stay installable offline, e.g.:

```bash
python3 -m pip install --no-build-isolation --no-deps --target /tmp/inst /app/pkg
```

and must expose the identical API when imported from an installed copy.
