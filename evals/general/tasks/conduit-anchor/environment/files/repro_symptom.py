"""A minimal reproduction of the pytest.approx() timedelta-comparison bug.

At the pinned parent commit, comparing datetime/timedelta values with
pytest.approx() using a RELATIVE tolerance expressed as a plain number
(e.g. rel=0.01) raises

    TypeError: relative tolerance for timedelta must be a timedelta, got float

Run it from anywhere; the installed pytest is the editable install of the
checkout at /app/src:

    python3 /app/repro_symptom.py

It prints a success line and exits 0 once the bug is fixed.
"""
from datetime import timedelta

import pytest

# relative tolerance as a plain number must be accepted and mean a fraction
# of the expected value: 10% of 100s is 10s, so 109s is inside and 111s is
# outside the window.
assert timedelta(seconds=100) == pytest.approx(timedelta(seconds=100.5), rel=0.01)
assert timedelta(seconds=109) == pytest.approx(timedelta(seconds=100), rel=0.1)
assert timedelta(seconds=111) != pytest.approx(timedelta(seconds=100), rel=0.1)

# timedelta scalars inside sequences and mappings must route through the
# timedelta comparison class instead of crashing.
assert [timedelta(seconds=105)] == pytest.approx([timedelta(seconds=100)], rel=0.05)
assert {"x": timedelta(seconds=105)} == pytest.approx(
    {"x": timedelta(seconds=100)}, rel=0.05
)

print("symptom resolved: relative tolerances work for timedelta comparisons")