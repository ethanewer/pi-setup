#!/bin/bash
# Oracle for quartz-relic: author the self-contained /app/dotkit package whose
# root module exposes dot(). Never reads /tests.
set -eu

PKG_DIR="/app/dotkit"
mkdir -p "$PKG_DIR"

# Root module: exposes the public scalar product (contract from instruction.md).
cat > "$PKG_DIR/__init__.py" <<'PY'
"""dotkit — scalar-product toolkit."""

from dotkit._core import dot

__all__ = ["dot"]
PY

# Internal implementation module (keeps the package self-contained).
cat > "$PKG_DIR/_core.py" <<'PY'
"""Internal scalar-product implementation."""


def dot(a, b):
    """Return the scalar (dot) product of two numeric sequences."""
    if len(a) != len(b):
        raise ValueError(
            "scalar product requires equal-length sequences "
            "(got %d and %d)" % (len(a), len(b))
        )
    total = 0
    for x, y in zip(a, b):
        total = total + x * y
    return total
PY

# Self-test on representative cases (not the grader's hidden ones).
python3 - <<'PY'
import sys
sys.path.insert(0, "/app")
import dotkit
from dotkit import dot

assert dotkit.dot is dot
assert dot([1, 2, 3], [4, 5, 6]) == 32
assert dot([], []) == 0
assert abs(dot([1.5, 2.25], [2.0, 0.5]) - 4.125) < 1e-12
assert dot((-2, -3), (-4, -5)) == 23
try:
    dot([1, 2], [1, 2, 3])
except ValueError:
    pass
else:
    raise AssertionError("mismatch must raise ValueError")
a, b = [1, 2], [3, 4]
dot(a, b)
assert a == [1, 2] and b == [3, 4], "inputs must not be mutated"
print("dotkit self-test OK")
PY

echo "solve.sh done -> $PKG_DIR"
ls -l "$PKG_DIR"
