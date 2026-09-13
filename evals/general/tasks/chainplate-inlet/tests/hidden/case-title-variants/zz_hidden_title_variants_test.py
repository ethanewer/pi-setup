"""Hidden case: title argument across a different group structure and
title strings than the upstream regression test uses (which uses 10 obs in
2 equal groups and the exact string "Custom MixedLM Summary")."""
import numpy as np
import pandas as pd
from statsmodels.regression.mixed_linear_model import MixedLM


def _fit(group_sizes, n_cov, seed=7):
    """Fit a MixedLM on unequal groups plus random standard-normal covariates."""
    rng = np.random.RandomState(seed)
    pid = np.repeat(np.arange(len(group_sizes)), group_sizes)
    n = len(pid)
    exog = rng.normal(size=(n, n_cov))
    endog = exog[:, 0] * 2.0 + rng.normal(scale=0.5, size=n)
    return MixedLM(endog, exog, groups=pid).fit()


def test_title_honored_with_unequal_groups():
    res = _fit([4, 4, 3, 5], 2)
    for title in (
        "Period 1 - Cohort A & B: group report #7",
        "  custom  whitespace  ",
        "'quoted' MixedLM \u00fc\u00df (\u00e9t\u00e9) 2026",
    ):
        summ = res.summary(title=title)
        assert summ.title == title, (summ.title, title)


def test_default_title_when_none():
    res = _fit([10, 10], 3, seed=3)
    assert res.summary().title == "Mixed Linear Model Regression Results"
    assert res.summary(title=None).title == "Mixed Linear Model Regression Results"