#!/bin/bash
# Oracle for sable-mesa: author the dotkit package (pyproject + flat-layout
# package with dotkit/core.py and a root-module re-export). Never reads /tests.
set -eu

PKG=/app/pkg
mkdir -p "$PKG/dotkit"

# ---- 1. Deliverable: /app/pkg/pyproject.toml ----
cat > "$PKG/pyproject.toml" <<'TOML'
[build-system]
requires = ["setuptools>=64"]
build-backend = "setuptools.build_meta"

[project]
name = "dotkit"
version = "1.3.0"
description = "Scalar-product toolkit for on-device telemetry"

[tool.setuptools]
packages = ["dotkit"]
TOML

# ---- 2. Deliverable: /app/pkg/dotkit/__init__.py (root module re-export) ----
cat > "$PKG/dotkit/__init__.py" <<'PY'
"""dotkit: scalar-product toolkit for on-device telemetry."""

from .core import dot

__all__ = ["dot"]
PY

# ---- 3. Supporting module: /app/pkg/dotkit/core.py (numeric kernel) ----
cat > "$PKG/dotkit/core.py" <<'PY'
"""Numeric kernel for dotkit."""


def dot(a, b):
    """Return the scalar (dot) product of two equal-length numeric sequences.

    Raises ValueError when the sequences have different lengths; returns 0
    for empty sequences.
    """
    if len(a) != len(b):
        raise ValueError("dot() requires sequences of equal length")
    total = 0
    for x, y in zip(a, b):
        total = total + x * y
    return total
PY

# ---- 4. Self-check: install offline and exercise all documented access paths
SITE=/tmp/sable_mesa_oracle_site
rm -rf "$SITE"
python3 -m pip install --quiet --no-index --no-deps --no-build-isolation \
    --target "$SITE" "$PKG"
PYTHONPATH="$SITE" python3 - <<'PY'
import dotkit
import dotkit.core
assert dotkit.dot([1, 2, 3], [4, 5, 6]) == 32
assert dotkit.core.dot([1.5, -2.0], [4.0, 3.0]) == 0.0
from dotkit import dot
assert dot([], []) == 0
try:
    dotkit.dot([1], [1, 2])
except ValueError:
    pass
else:
    raise SystemExit("expected ValueError on length mismatch")
print("oracle self-check ok")
PY

echo "solve.sh done -> $PKG/pyproject.toml and $PKG/dotkit/__init__.py"
ls -l "$PKG/pyproject.toml" "$PKG/dotkit/__init__.py" "$PKG/dotkit/core.py"
