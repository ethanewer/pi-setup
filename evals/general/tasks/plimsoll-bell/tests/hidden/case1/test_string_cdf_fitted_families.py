"""Hidden case 1 (plimsoll-bell): string-named null + fitted loc/scale for
distribution families the upstream regression test does not use.

The upstream regression test (test_gh25448) covers only 'norm' with the
standard-normal fit of a single rng.normal(size=100) sample. These tests
drive the same code path -- `kstest(x, "<name>", args=<params>)` resolving a
string CDF name with separately-passed parameters -- for the two-parameter
(loc, scale) families uniform/laplace/logistic/cauchy/expon with genuinely
non-trivial fitted locations and scales, plus 'norm' itself under both
one-sided alternatives and on a shifted, scaled sample. Every case compares
the string-name statistic AND p-value against the equivalent callable-CDF
form of the same null, so a fix that special-cases 'norm' by re-tuning
nothing here is caught only where it must be, and a fix that drops the
parameters entirely (statistically wrong but non-crashing) fails on the
shifted-sample cases because the statistics then disagree.
"""
import numpy as np
import pytest
from scipy import stats


def _stats_pair(x, name, params):
    cdf = getattr(stats.distributions, name).cdf
    ref = stats.kstest(x, lambda t, *p: cdf(t, *p), args=params)
    got = stats.kstest(x, name, args=params)
    return ref, got


FAMILIES = ["uniform", "laplace", "logistic", "cauchy", "expon"]


def _sample(rng, rv):
    # draws that give non-trivial fitted loc/scale (shifted, scaled away
    # from the standard location-scale defaults)
    return rv.rvs(size=120, random_state=rng)


@pytest.mark.parametrize("name", FAMILIES)
def test_two_param_families_agree_with_callable(name):
    rng = np.random.default_rng(9917 + len(name))
    dist = getattr(stats, name)
    if name == "uniform":
        rv = dist(loc=3.7, scale=5.2)
    elif name == "expon":
        rv = dist(loc=-1.4, scale=2.3)
    else:
        rv = dist(loc=2.1, scale=1.6)
    x = _sample(rng, rv)
    loc, scale = getattr(stats, name).fit(x)
    assert abs(loc - 0.0) > 0.5 or abs(scale - 1.0) > 0.2, "fit must be non-trivial"

    ref, got = _stats_pair(x, name, (loc, scale))
    rtol = 1e-10
    assert abs(got.statistic - ref.statistic) / abs(ref.statistic) < rtol
    assert abs(got.pvalue - ref.pvalue) / abs(ref.pvalue) < 1e-9


def test_norm_one_sided_alternatives():
    rng = np.random.default_rng(254482544825448)
    x = rng.normal(loc=1.3, scale=2.2, size=90)
    loc, scale = stats.norm.fit(x)
    assert abs(loc) > 0.5 and abs(scale - 1.0) > 0.2, "fit must be non-trivial"
    for alternative in ("less", "greater"):
        ref = stats.kstest(x, lambda t, u, s: stats.norm.cdf(t, u, s),
                           args=(loc, scale), alternative=alternative)
        got = stats.kstest(x, "norm", args=(loc, scale), alternative=alternative)
        assert abs(got.statistic - ref.statistic) / abs(ref.statistic) < 1e-10
        assert abs(got.pvalue - ref.pvalue) / abs(ref.pvalue) < 1e-9


def test_norm_shifted_scaled_sample_uses_args():
    # a 'fix' that silently ignores args would compute the statistic of the
    # standard normal against this shifted/scaled sample and disagree loudly.
    rng = np.random.default_rng(42)
    x = rng.normal(loc=-4.0, scale=0.7, size=150)
    loc, scale = stats.norm.fit(x)
    ref = stats.kstest(x, lambda t, u, s: stats.norm.cdf(t, u, s),
                       args=(loc, scale))
    got = stats.kstest(x, "norm", args=(loc, scale))
    assert abs(got.statistic - ref.statistic) / abs(ref.statistic) < 1e-10
    assert abs(got.statistic - 0.5) > 0.05, "sample must not be standard normal"