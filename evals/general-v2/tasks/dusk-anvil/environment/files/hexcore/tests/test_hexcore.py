import numpy as np
import pytest
import hexcore


def test_zoom():
    a = np.array([[1.0, -2.0], [3.5, 0.0]])
    out = hexcore.zoom(a)
    assert out.dtype == np.float64
    np.testing.assert_allclose(out, 2.0 * a)


def test_mirror():
    a = np.array([[1.0, 2.0], [3.0, 4.0]])
    np.testing.assert_allclose(hexcore.mirror(a), [[4.0, 3.0], [2.0, 1.0]])


def test_total():
    assert hexcore.total([1, 2, 3.5]) == 6.5


def test_as_floats():
    out = hexcore.as_floats([1, "2", 3.5])
    assert out.dtype == np.float64
    np.testing.assert_allclose(out, [1.0, 2.0, 3.5])


def test_defaults_are_infinite():
    assert hexcore.DEFAULT_LO == float("-inf")
    assert hexcore.DEFAULT_HI == float("inf")


def test_clamp_contiguous():
    a = np.array([-5.0, 0.0, 3.0, 9.0])
    hexcore.clamp_inplace(a, -1.0, 4.0)
    np.testing.assert_allclose(a, [-1.0, 0.0, 3.0, 4.0])


def test_clamp_transposed_view_writes_back():
    base = np.arange(9, dtype=np.float64).reshape(3, 3)
    view = base.T
    hexcore.clamp_inplace(view, 1.5, 6.5)
    np.testing.assert_allclose(view, np.clip(np.arange(9, dtype=np.float64).reshape(3, 3).T, 1.5, 6.5))
    np.testing.assert_allclose(base, np.clip(np.arange(9, dtype=np.float64).reshape(3, 3), 1.5, 6.5).T.T)
    # the base array must see the same writes
    assert base[0, 0] == 1.5


def test_clamp_rejects_bad_inputs():
    with pytest.raises(TypeError):
        hexcore.clamp_inplace([1.0, 2.0], 0.0, 1.0)
    with pytest.raises(TypeError):
        hexcore.clamp_inplace(np.array([1, 2]), 0.0, 1.0)
    ro = np.array([9.0, -9.0]); ro.flags.writeable = False
    with pytest.raises(ValueError):
        hexcore.clamp_inplace(ro, 0.0, 1.0)
