"""Unit tests for the avocet statistics module."""
import math

import pytest

from avocet import bandwidth, jitter, mean, median, pct


def test_mean_of_samples():
    assert mean([1, 2, 3, 4]) == pytest.approx(2.5)


def test_mean_empty_raises():
    with pytest.raises(ValueError):
        mean([])


def test_median_odd_count():
    assert median([3, 1, 2]) == 2


def test_median_even_count():
    assert median([4, 1, 2, 3]) == pytest.approx(2.5)


def test_median_empty_raises():
    with pytest.raises(ValueError):
        median([])


def test_pct_nearest_rank():
    seq = [9, 1, 5, 7, 3]
    assert pct(seq, 50) == 5
    assert pct(seq, 100) == 9


def test_pct_invalid_raises():
    with pytest.raises(ValueError):
        pct([1, 2], 0)
    with pytest.raises(ValueError):
        pct([1, 2], 101)


def test_bandwidth_basic():
    assert bandwidth(1000, 0.5) == pytest.approx(2000.0)


def test_bandwidth_invalid_raises():
    with pytest.raises(ValueError):
        bandwidth(10, 0)


def test_jitter_single_sample_raises():
    with pytest.raises(ValueError):
        jitter([1])


def test_jitter_constant_series():
    assert jitter([5, 5, 5, 5]) == pytest.approx(0.0)


def test_jitter_positive():
    assert jitter([1, 2, 3, 4, 5]) == pytest.approx(math.sqrt(2.5))
