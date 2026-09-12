"""Hidden case 2 for conduit-anchor: validation parity for relative
tolerances and type discipline.

At the parent commit, a negative or NaN relative tolerance is never
validated (pytest.approx immediately raises TypeError because the number
itself is rejected), and a timedelta is still accepted as a relative
tolerance. After the fix, relative tolerances are validated the same way the
plain-number approx does: negative and NaN must raise ValueError with the
documented messages, and only int/float are accepted for rel.
"""
from datetime import timedelta

import pytest


def test_negative_rel_is_rejected():
    with pytest.raises(ValueError, match="relative tolerance can't be negative"):
        pytest.approx(timedelta(seconds=1), rel=-0.25)


def test_nan_rel_is_rejected():
    with pytest.raises(ValueError, match="relative tolerance can't be NaN"):
        pytest.approx(timedelta(seconds=1), rel=float("nan"))


def test_rel_must_be_a_number_not_timedelta():
    with pytest.raises(TypeError, match="must be a number"):
        pytest.approx(timedelta(seconds=1), rel=timedelta(seconds=1))


def test_rel_must_be_a_number_not_str():
    with pytest.raises(TypeError, match="must be a number"):
        pytest.approx(timedelta(seconds=1), rel="0.1")


def test_negative_abs_is_rejected():
    with pytest.raises(ValueError, match="absolute tolerance can't be negative"):
        pytest.approx(timedelta(seconds=1), abs=timedelta(seconds=-1))


def test_int_rel_works():
    # rel=1 means a 100% relative tolerance: everything within a factor of 2
    assert timedelta(seconds=150) == pytest.approx(
        timedelta(seconds=100), rel=1
    )
    # rel=2 means 200%: anything within 2x the expected magnitude
    assert timedelta(seconds=250) == pytest.approx(
        timedelta(seconds=100), rel=2
    )