#!/usr/bin/env python3
"""Apply the conduit-anchor fix to src/_pytest/python_api.py in place.

Three spliced edits into the approximate-comparison machinery:

1. `_approx_scalar` routes datetime/timedelta scalars that occur inside
   sequences/mappings to ApproxTimedelta instead of ApproxScalar.
2. ApproxTimedelta accepts a plain int/float as the relative tolerance (a
   fraction of the expected value) instead of requiring a timedelta, and
   validates negative / NaN relative tolerances and negative timedelta
   absolute tolerances with the same messages the plain-number classes use.
3. The effective tolerance becomes abs when only abs is given, rel *
   abs(expected) when only rel is given, and max(abs, rel * abs(expected))
   (both timedeltas) when both are given.

Idempotent: exits 0 if the file already carries the fix. Exits non-zero if
any splice target cannot be found (the tree drifted from the pinned commit).
"""

import sys
from pathlib import Path

path = Path(sys.argv[1] if len(sys.argv) > 1 else "src/_pytest/python_api.py")
src = path.read_text(encoding="utf-8")

EDITS = [
    # 1. route datetime/timedelta scalars to ApproxTimedelta
    (
        "    def _approx_scalar(self, x) -> ApproxScalar:\n"
        "        if isinstance(x, Decimal):\n"
        "            return ApproxDecimal(x, rel=self.rel, abs=self.abs, nan_ok=self.nan_ok)\n"
        "        return ApproxScalar(x, rel=self.rel, abs=self.abs, nan_ok=self.nan_ok)\n",
        "    def _approx_scalar(self, x) -> ApproxBase:\n"
        "        if isinstance(x, Decimal):\n"
        "            return ApproxDecimal(x, rel=self.rel, abs=self.abs, nan_ok=self.nan_ok)\n"
        "        if isinstance(x, (datetime, timedelta)):\n"
        "            return ApproxTimedelta(x, rel=self.rel, abs=self.abs, nan_ok=self.nan_ok)\n"
        "        return ApproxScalar(x, rel=self.rel, abs=self.abs, nan_ok=self.nan_ok)\n",
    ),
    # 2.+3. ApproxTimedelta validation and effective-tolerance computation
    (
        "        if rel is not None and not isinstance(rel, timedelta):\n"
        "            raise TypeError(\n"
        '                f"relative tolerance for timedelta must be a "\n'
        '                f"timedelta, got {type(rel).__name__}"\n'
        "            )\n"
        "        tolerance = max(t for t in (abs, rel) if t is not None)\n",
        "        if rel is not None:\n"
        "            if not isinstance(rel, (int, float)):\n"
        "                raise TypeError(\n"
        '                    f"relative tolerance for timedelta must be a "\n'
        '                    f"number, got {type(rel).__name__}"\n'
        "                )\n"
        "            if rel < 0:\n"
        '                raise ValueError(f"relative tolerance can\'t be negative: {rel}")\n'
        "            if math.isnan(rel):\n"
        '                raise ValueError("relative tolerance can\'t be NaN.")\n'
        "        if abs is not None and abs < timedelta(0):\n"
        '            raise ValueError(f"absolute tolerance can\'t be negative: {abs}")\n'
        "        # effective tolerance: abs is a timedelta; rel is a number, so\n"
        "        # rel * abs(expected) is a timedelta\n"
        "        abs_tolerance = abs\n"
        "        rel_tolerance = rel * builtins.abs(expected) if rel is not None else None\n"
        "        if abs_tolerance is not None and rel_tolerance is not None:\n"
        "            tolerance = max(abs_tolerance, rel_tolerance)\n"
        "        else:\n"
        "            tolerance = abs_tolerance if abs_tolerance is not None else rel_tolerance\n",
    ),
]

for old, new in EDITS:
    if new in src:
        continue  # already applied (idempotent)
    if old not in src:
        print("splice target not found; tree drifted from the pinned commit", file=sys.stderr)
        sys.exit(1)
    if src.count(old) != 1:
        print("splice target is not unique; aborting", file=sys.stderr)
        sys.exit(1)
    src = src.replace(old, new, 1)

path.write_text(src, encoding="utf-8")
print("src/_pytest/python_api.py patched")