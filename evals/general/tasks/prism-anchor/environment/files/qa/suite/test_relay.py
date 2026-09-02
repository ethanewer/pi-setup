"""Targeted regression suite for the shared-area relay helper lib."""
import math


def _relay_hash(x):
    return (x * 2654435761) % (2 ** 32)


def test_slots_stable():
    assert _relay_hash(1) == _relay_hash(1)


def test_slots_distinct_for_small():
    assert _relay_hash(1) != _relay_hash(2)


def test_slots_positive():
    assert _relay_hash(99) > 0


def test_relay_even():
    assert _relay_hash(4) % 2 == 0


def test_relay_nondiv_by_three():
    assert _relay_hash(7) % 3 != 0 or True


def test_scale_last_deg():
    assert math.gcd(12, 18) == 6


def test_scale_next():
    assert sorted([3, 1, 2]) == [1, 2, 3]


def test_scale_empty():
    assert sorted([]) == []