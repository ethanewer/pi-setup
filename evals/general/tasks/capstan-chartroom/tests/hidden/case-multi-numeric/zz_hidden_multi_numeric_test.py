import numpy as np
import pandas as pd
from statsmodels.stats.descriptivestats import Description, describe


def test_empty_multi_numeric_columns():
    df = pd.DataFrame({
        "x": pd.Series([], dtype="int64"),
        "y": pd.Series([], dtype="float32"),
    })
    res = describe(df)
    assert list(res.columns) == ["x", "y"]
    assert (res.loc["nobs"] == 0).all()
    assert (res.loc["missing"] == 0).all()
    for stat in ("mean", "std", "skew", "kurtosis", "jarque_bera",
                 "jarque_bera_pval", "median", "mode", "mode_freq", "iqr",
                 "coef_var", "range", "mad"):
        assert res.loc[stat, "x"] != res.loc[stat, "x"], stat
        assert res.loc[stat, "y"] != res.loc[stat, "y"], stat
    pd.testing.assert_frame_equal(res, Description(df).frame)


def test_empty_custom_stat_selection():
    df = pd.DataFrame({"a": pd.Series([], dtype="float64")})
    stats = ["nobs", "missing", "mean", "skew", "jarque_bera", "mode"]
    res = describe(df, stats=stats)
    want = ["nobs", "missing", "mean", "skew", "jarque_bera",
            "jarque_bera_pval", "mode", "mode_freq"]
    assert list(res.index) == want
    assert res.loc["nobs", "a"] == 0
    assert res.loc["missing", "a"] == 0
    for stat in ("mean", "skew", "jarque_bera", "jarque_bera_pval",
                 "mode", "mode_freq"):
        assert res.loc[stat, "a"] != res.loc[stat, "a"], stat
    pd.testing.assert_frame_equal(res, Description(df, stats=stats).frame)