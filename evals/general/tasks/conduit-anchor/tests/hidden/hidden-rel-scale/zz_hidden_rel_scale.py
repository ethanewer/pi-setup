"""Hidden case 1 for conduit-anchor: relative-tolerance scaling at unusual
magnitudes and on negative expected values.

The upstream regression tests for this bug only use positive whole-second
timedeltas; these exercise microsecond resolution, negative expected values
(where the relative tolerance must be a fraction of abs(expected)), and
multi-day magnitudes. All fail at the parent commit (pytest.approx rejects a
plain number as the relative tolerance for timedelta comparisons).
"""
from datetime import timedelta

import pytest


def test_rel_fraction_of_microsecond_delta():
    # 5% of 100 microseconds = 5 microseconds
    assert timedelta(microseconds=105) == pytest.approx(
        timedelta(microseconds=100), rel=0.05
    )
    # 20 microseconds is 20% of the expected value, outside the 5% window
    assert timedelta(microseconds=120) != pytest.approx(
        timedelta(microseconds=100), rel=0.05
    )


def test_rel_negative_expected_scales_with_abs():
    # rel is a fraction of abs(expected): 10% of abs(-100s) = 10s
    assert timedelta(seconds=-109) == pytest.approx(
        timedelta(seconds=-100), rel=0.1
    )
    assert timedelta(seconds=-111) != pytest.approx(
        timedelta(seconds=-100), rel=0.1
    )


def test_rel_large_magnitude_days():
    # 10% of 10 days = 1 day
    assert timedelta(days=9) == pytest.approx(timedelta(days=10), rel=0.1)
    # 12 days is 20% away, outside the 10% window
    assert timedelta(days=12) != pytest.approx(timedelta(days=10), rel=0.1)


def test_rel_combined_abs_seconds_and_micros():
    # rel=0.2 of 100 seconds = 20s; abs=3s; effective tolerance 20s
    assert timedelta(seconds=115) == pytest.approx(
        timedelta(seconds=100), rel=0.2, abs=timedelta(seconds=3)
    )
    # rel=0.01 of 100 seconds = 1s; abs=5s; effective tolerance 5s
    assert timedelta(seconds=104) == pytest.approx(
        timedelta(seconds=100), rel=0.01, abs=timedelta(seconds=5)
    )
    # 106s is 6s away, outside the 5s effective tolerance
    assert timedelta(seconds=106) != pytest.approx(
        timedelta(seconds=100), rel=0.01, abs=timedelta(seconds=5)
    )