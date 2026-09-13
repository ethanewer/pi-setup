import pandas as pd
from statsmodels.stats.descriptivestats import Description, describe


def test_empty_series_input():
    s = pd.Series([], dtype="float64", name="measure")
    res = describe(s)
    assert isinstance(res, pd.DataFrame)
    assert list(res.columns) == ["measure"]
    assert res.loc["nobs", "measure"] == 0
    assert res.loc["missing", "measure"] == 0
    assert res.loc["mean", "measure"] != res.loc["mean", "measure"]
    assert res.loc["mode", "measure"] != res.loc["mode", "measure"]
    pd.testing.assert_frame_equal(res, Description(s).frame)


def test_empty_nullable_int():
    df = pd.DataFrame({"a": pd.Series([], dtype="Int64")})
    res = describe(df)
    assert list(res.columns) == ["a"]
    assert res.loc["nobs", "a"] == 0
    assert res.loc["missing", "a"] == 0
    assert res.loc["mean", "a"] != res.loc["mean", "a"]
    assert res.loc["mode", "a"] != res.loc["mode", "a"]