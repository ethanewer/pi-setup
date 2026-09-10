"""Unit tests for the wigeon signal-scaling module."""
import math

import pytest

from wigeon import clip, compress, db_to_gain, gain_to_db, integrate


def test_db_to_gain_zero_is_unity():
    assert db_to_gain(0.0) == pytest.approx(1.0)


def test_db_to_gain_positive():
    assert db_to_gain(20.0) == pytest.approx(10.0)


def test_db_to_gain_negative():
    assert db_to_gain(-20.0) == pytest.approx(0.1)


def test_gain_to_db_round_trip():
    for gain in (0.5, 1.0, 2.0, 8.0):
        assert db_to_gain(gain_to_db(gain)) == pytest.approx(gain)


def test_gain_to_db_nonpositive_raises():
    with pytest.raises(ValueError):
        gain_to_db(0.0)
    with pytest.raises(ValueError):
        gain_to_db(-3.0)


def test_clip_within_range_unchanged():
    assert clip(0.5, 0.0, 1.0) == 0.5


def test_clip_above_ceiling():
    assert clip(1.5, 0.0, 1.0) == 1.0


def test_clip_below_floor():
    assert clip(-0.5, 0.0, 1.0) == 0.0


def test_clip_inverted_bounds_raises():
    with pytest.raises(ValueError):
        clip(0.5, 1.0, 0.0)


def test_compress_below_ceiling_is_unity():
    assert compress(0.5, 1.0) == 1.0


def test_compress_above_ceiling():
    assert compress(8.0, 2.0) == pytest.approx(0.25)


def test_compress_nonpositive_raises():
    with pytest.raises(ValueError):
        compress(0.0, 1.0)
    with pytest.raises(ValueError):
        compress(1.0, -1.0)


def test_integrate_empty_is_zero():
    assert integrate([]) == 0.0


def test_integrate_rms():
    assert integrate([1.0, -1.0, 1.0, -1.0]) == pytest.approx(1.0)
    assert integrate([3.0, 4.0]) == pytest.approx(3.5355339)
