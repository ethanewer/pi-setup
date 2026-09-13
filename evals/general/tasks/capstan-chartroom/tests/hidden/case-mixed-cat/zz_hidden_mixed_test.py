import numpy as np
import pandas as pd
from statsmodels.stats.descriptivestats import describe


def test_empty_mixed_top_freq():
    df = pd.DataFrame({
        "a": pd.Series([], dtype="float64"),
        "b": pd.Series([], dtype="category"),
    })
    res = describe(df, stats=["nobs", "missing", "mean", "top", "freq"])
    assert list(res.columns) == ["a", "b"]
    assert (res.loc["nobs"] == 0).all()
    assert (res.loc["missing"] == 0).all()
    assert res.loc["mean", "a"] != res.loc["mean", "a"]
    assert res.loc["top_1", "b"] is None
    assert res.loc["freq_1", "b"] != res.loc["freq_1", "b"]
    assert res.loc["top_1", "a"] != res.loc["top_1", "a"] or res.loc["top_1", "a"] is None


def test_empty_ci_bounds():
    # ci (upper/lower) on a 0-row frame must be produced NaN, not raise
    df = pd.DataFrame({"a": pd.Series([], dtype="float64")})
    res = describe(df, stats=["ci", "mean"])
    assert res.loc["upper_ci", "a"] != res.loc["upper_ci", "a"]
    assert res.loc["lower_ci", "a"] != res.loc["lower_ci", "a"]