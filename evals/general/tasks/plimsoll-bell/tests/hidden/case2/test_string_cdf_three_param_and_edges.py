"""Hidden case 2 (plimsoll-bell): string-named null with three parameters
and argument-shape edge cases.

The upstream regression test covers a two-parameter (loc, scale) normal null.
These tests exercise the same code path -- string CDF name plus separately
passed parameters -- with a three-parameter (shape, loc, scale) family
(gamma), with parameters passed as numpy scalars instead of Python floats,
with a large sample, and the preserved no-args string form. A partial fix
that only taught the 'norm' special case about loc/scale, or one that chokes
on non-float argument arrays, fails here; the no-args assertions guard the
behaviour the fix must preserve.
"""
import numpy as np
import pytest
from scipy import stats


def test_gamma_three_param_string_null():
    rng = np.random.default_rng(20260828)
    shape, loc, scale = 2.4, 1.0, 0.6
    x = stats.gamma.rvs(shape, loc=loc, scale=scale, size=200, random_state=rng)
    fit = stats.gamma.fit(x)  # (shape, loc, scale)
    assert len(fit) == 3

    ref = stats.kstest(x, lambda t, a, l, s: stats.gamma.cdf(t, a, l, s),
                       args=tuple(fit))
    got = stats.kstest(x, "gamma", args=tuple(fit))
    assert abs(got.statistic - ref.statistic) / abs(ref.statistic) < 1e-10
    assert abs(got.pvalue - ref.pvalue) / abs(ref.pvalue) < 1e-9


def test_norm_args_as_numpy_scalars():
    rng = np.random.default_rng(7)
    x = rng.normal(size=80)
    loc, scale = stats.norm.fit(x)
    args_np = (np.float64(loc), np.float64(scale))

    ref = stats.kstest(x, lambda t, u, s: stats.norm.cdf(t, u, s), args=args_np)
    got = stats.kstest(x, "norm", args=args_np)
    assert abs(got.statistic - ref.statistic) / abs(ref.statistic) < 1e-10


def test_norm_large_sample():
    rng = np.random.default_rng(310)
    x = rng.normal(loc=0.5, scale=3.1, size=2000)
    loc, scale = stats.norm.fit(x)
    ref = stats.kstest(x, lambda t, u, s: stats.norm.cdf(t, u, s),
                       args=(loc, scale))
    got = stats.kstest(x, "norm", args=(loc, scale))
    assert abs(got.statistic - ref.statistic) / abs(ref.statistic) < 1e-10
    assert abs(got.pvalue - ref.pvalue) / abs(ref.pvalue) < 1e-9


def test_string_norm_without_args_still_equals_ndtr():
    rng = np.random.default_rng(5)
    x = rng.normal(size=60)
    ref = stats.kstest(x, stats.norm.cdf)
    got = stats.kstest(x, "norm")
    assert abs(got.statistic - ref.statistic) / abs(ref.statistic) < 1e-12
    assert abs(got.pvalue - ref.pvalue) / abs(ref.pvalue) < 1e-12


@pytest.mark.parametrize("seed", [11, 23, 47])
def test_repeated_seeds_stable(seed):
    rng = np.random.default_rng(seed)
    x = rng.laplace(loc=2.0, scale=1.4, size=140)
    params = stats.laplace.fit(x)
    ref = stats.kstest(x, lambda t, l, s: stats.laplace.cdf(t, l, s), args=tuple(params))
    got = stats.kstest(x, "laplace", args=tuple(params))
    assert got.statistic == pytest.approx(ref.statistic, rel=1e-10)
    assert got.pvalue == pytest.approx(ref.pvalue, rel=1e-9)