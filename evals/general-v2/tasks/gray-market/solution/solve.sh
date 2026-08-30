#!/usr/bin/env bash
#
# Oracle for the "gray-market" task.
# Builds the ledger-check wheel the same way an agent should: completes the
# PEP 517 metadata and entry point, implements the documented parser, and
# builds the wheel into /app/dist. Does not read /tests.
set -euo pipefail

PKG=/app/pkg
SRC="$PKG/src/ledgercheck"
mkdir -p "$SRC"

# 1) complete the project metadata + console entry point ----------------------
cat > "$PKG/pyproject.toml" <<'TOML'
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "ledger-check"
version = "0.4.2"
description = "Gray-market ledger amount normalizer."
readme = "README.md"
requires-python = ">=3.9"

[tool.setuptools]
package-dir = { "" = "src" }
packages = ["ledgercheck"]

[project.scripts]
ledger-check = "ledgercheck.cli:main"
TOML

# 2) implement the public parser -----------------------------------------------
cat > "$SRC/__init__.py" <<'PY'
import re
from decimal import Decimal, ROUND_HALF_UP


def normalize_amount(text):
    """Return the integer number of cents in ``text``.

    Contract (see README.md): whitespace trimmed, optional leading sign,
    one leading currency symbol among $ euro pound yen stripped, comma is a
    three-digit thousands separator, decimal half-away-from-zero rounding to
    the nearest cent. Malformed/empty input raises ValueError.
    """
    if not isinstance(text, str):
        raise ValueError("amount must be a string")
    t = text.strip()
    if not t:
        raise ValueError("amount must not be empty")
    sign = 1
    if t[0] in "+-":
        sign = -1 if t[0] == "-" else 1
        t = t[1:].strip()
    if t[:1] in "$€£¥":
        t = t[1:]
    if not re.fullmatch(r"\d{1,3}(,\d{3})*(\.\d+)?|\d+(\.\d+)?", t):
        raise ValueError(f"invalid amount: {text!r}")
    cents = (Decimal(t.replace(",", "")) * 100).quantize(
        Decimal("1"), ROUND_HALF_UP
    )
    return sign * int(cents)
PY

# 3) build the wheel into /app/dist -----------------------------------------
rm -rf /app/dist
mkdir -p /app/dist
python3 -m pip wheel --no-build-isolation --no-deps -w /app/dist "$PKG"

# sanity: exactly one wheel must have been produced
WHEELS=( /app/dist/*.whl )
if [ "${#WHEELS[@]}" -ne 1 ]; then
  echo "oracle error: expected exactly one wheel, found ${#WHEELS[@]}" >&2
  exit 1
fi
echo "built ${WHEELS[0]}"