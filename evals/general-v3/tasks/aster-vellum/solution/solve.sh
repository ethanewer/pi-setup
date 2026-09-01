#!/bin/bash
# Oracle for aster-vellum: implement dot_product in the package root module
# per /app/pkg/README.md, then sanity-check both import modes. Never reads /tests.
set -eu

INIT="/app/pkg/src/dotkit/__init__.py"

cat > "$INIT" <<'PY'
"""dotkit — minimal vector math toolkit.

The public API lives here, in the package root module.
"""

__all__ = ["dot_product"]


def dot_product(a, b):
    """Return the scalar (dot) product of two numeric sequences.

    See README.md for the full contract: int/float result typing, ValueError
    on length mismatch (compared up front), TypeError on non-numeric
    elements, no input mutation.
    """
    va = list(a)
    vb = list(b)
    if len(va) != len(vb):
        raise ValueError(
            "dot_product: length mismatch: %d vs %d" % (len(va), len(vb))
        )
    all_int = True
    for v in va:
        if isinstance(v, float):
            all_int = False
        elif not isinstance(v, int):
            raise TypeError("dot_product: non-numeric element %r" % (v,))
    for v in vb:
        if isinstance(v, float):
            all_int = False
        elif not isinstance(v, int):
            raise TypeError("dot_product: non-numeric element %r" % (v,))
    total = 0
    for x, y in zip(va, vb):
        total += x * y
    return total if all_int else float(total)
PY

chmod +x "$INIT" || true

# Sanity: source-tree import mode.
python3 - <<'PY'
import sys
sys.path.insert(0, "/app/pkg/src")
import dotkit

assert dotkit.dot_product.__module__ == "dotkit", dotkit.dot_product.__module__
assert dotkit.dot_product([1, 2, 3], [4, 5, 6]) == 32
assert isinstance(dotkit.dot_product([1, 2, 3], [4, 5, 6]), int)
assert dotkit.dot_product((), ()) == 0
assert dotkit.dot_product([1.5, 2.5], [2.0, 4.0]) == 13.0
assert isinstance(dotkit.dot_product([1], [2.0]), float)
try:
    dotkit.dot_product([1, 2], [1])
except ValueError:
    pass
else:
    raise AssertionError("expected ValueError")
try:
    dotkit.dot_product([1, "x"], [1, 2])
except TypeError:
    pass
else:
    raise AssertionError("expected TypeError")
print("source-mode sanity OK")
PY

# Sanity: offline installed mode.
rm -rf /tmp/dk_oracle_inst
python3 -m pip install --no-build-isolation --no-deps --quiet \
    --target /tmp/dk_oracle_inst /app/pkg
python3 - <<'PY'
import sys
sys.path.insert(0, "/tmp/dk_oracle_inst")
import dotkit
assert dotkit.dot_product.__module__ == "dotkit"
assert dotkit.dot_product(tuple(range(4)), (2, 2, 2, 2)) == 12
print("installed-mode sanity OK")
PY

echo "solve.sh done -> $INIT"
ls -l "$INIT"
