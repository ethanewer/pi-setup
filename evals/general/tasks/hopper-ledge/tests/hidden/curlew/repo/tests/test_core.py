"""Unit tests for the curlew grid encoding module."""
import pytest

from curlew import encode, neighbouring

ALPHABET = "0123456789bcdefghjkmnpqrstuvwxyz"


def test_encode_length():
    for precision in (1, 3, 6, 10):
        assert len(encode(0.0, 0.0, precision)) == precision


def test_encode_charset():
    code = encode(12.34, -56.78, 8)
    assert all(c in ALPHABET for c in code)


def test_encode_is_deterministic():
    assert encode(41.9, 2.6, 6) == encode(41.9, 2.6, 6)


def test_encode_out_of_range_raises():
    with pytest.raises(ValueError):
        encode(91.0, 0.0)
    with pytest.raises(ValueError):
        encode(0.0, -181.0)


def test_encode_nearby_points_share_prefix():
    a = encode(0.0, 0.0, 6)
    b = encode(0.0002, 0.0002, 6)
    assert a[:5] == b[:5]


def test_encode_opposite_hemispheres_differ_early():
    north = encode(89.9, 179.9, 6)
    south = encode(-89.9, -179.9, 6)
    assert north != south
    assert north[0] != south[0]


def test_encode_integer_coordinates():
    assert encode(52.0, 13.0, 1) in ALPHABET


def test_neighbouring_rejects_missing_char():
    with pytest.raises(ValueError):
        neighbouring("")


def test_neighbouring_rejects_bad_char():
    with pytest.raises(ValueError):
        neighbouring("aX9000")


def test_neighbouring_returns_distinct_neighbours():
    cell = encode(1.0, 1.0, 3)
    nbrs = neighbouring(cell)
    assert len(nbrs) == len(ALPHABET) - 1
    assert cell not in nbrs
