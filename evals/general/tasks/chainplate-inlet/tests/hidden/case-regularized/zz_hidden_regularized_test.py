"""Hidden case: the summary title must be honored on the fit_regularized()
public path (the upstream regression test only exercises the plain fit())."""
import warnings

import numpy as np
import pandas as pd
from statsmodels.base import _penalties as penalties
from statsmodels.regression.mixed_linear_model import MixedLM


def _toy(seed=2):
    rng = np.random.RandomState(seed)
    pid = np.repeat([0, 1], 5)
    x0 = np.repeat([1], 10)
    x1 = rng.normal(size=10)
    x2 = rng.normal(size=10)
    y = rng.normal(size=10)
    df = pd.DataFrame({"y": y, "pid": pid, "x0": x0, "x1": x1, "x2": x2})
    return (df["y"].values, df[["x0", "x1", "x2"]].values, df["pid"].values)


def test_title_regularized_fit():
    endog, exog, groups = _toy()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        res = MixedLM(endog, exog, groups=groups).fit_regularized()
    title = "Regularized MixedLM: alpha ladder report"
    summ = res.summary(title=title)
    assert summ.title == title, summ.title
    assert res.summary().title == "Mixed Linear Model Regression Results"


def test_title_regularized_with_names():
    endog, exog, groups = _toy(seed=5)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        res = MixedLM(endog, exog, groups=groups).fit_regularized(
            method=penalties.L2()
        )
    title = "L2-Penalized Fit Summary"
    summ = res.summary(title=title, yname="response", xname_re=["Random Effect"])
    assert summ.title == title, summ.title
    assert "Random Effect" in list(summ.tables[1].index.values)