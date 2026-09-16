"""Hidden case: the title argument must combine cleanly with the other
summary arguments (yname, xname_fe, xname_re): the title is honored AND the
named-parameter table and dependent-variable label still render from the
other arguments. A fix that only special-cased the title would fail here."""
import numpy as np
import pandas as pd
from statsmodels.regression.mixed_linear_model import MixedLM


def test_title_with_other_summary_args():
    pid = np.repeat([0, 1], 5)
    x0 = np.repeat([1], 10)
    x1 = [1, 5, 7, 3, 5, 1, 2, 6, 9, 8]
    x2 = [6, 2, 1, 0, 1, 4, 3, 8, 2, 1]
    y = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    df = pd.DataFrame({"y": y, "pid": pid, "x0": x0, "x1": x1, "x2": x2})
    endog = df["y"].values
    exog = df[["x0", "x1", "x2"]].values
    groups = df["pid"].values
    res = MixedLM(endog, exog, groups=groups).fit()

    title = "Total Yield Summary"
    summ = res.summary(
        title=title,
        yname="yield_kg",
        xname_fe=["Intercept", "Sunlight", "Rainfall"],
        xname_re=["Trial Effect"],
    )
    assert summ.title == title, summ.title
    # Second table is the parameter table with the custom names substituted
    # for the fixed and random effects.
    assert list(summ.tables[1].index.values) == [
        "Intercept", "Sunlight", "Rainfall", "Trial Effect",
    ]
    text = summ.as_text()
    assert "yield_kg" in text
    assert "Sunlight" in text


def test_title_survives_multiple_calls():
    pid = np.repeat([0, 1], 5)
    x0 = np.repeat([1], 10)
    x1 = [1, 5, 7, 3, 5, 1, 2, 6, 9, 8]
    x2 = [6, 2, 1, 0, 1, 4, 3, 8, 2, 1]
    y = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    df = pd.DataFrame({"y": y, "pid": pid, "x0": x0, "x1": x1, "x2": x2})
    endog = df["y"].values
    exog = df[["x0", "x1", "x2"]].values
    groups = df["pid"].values
    res = MixedLM(endog, exog, groups=groups).fit()

    a = res.summary(title="Report One").as_text()
    b = res.summary(title="Report Two").as_text()
    c = res.summary().as_text()
    assert "Report One" in a
    assert "Report Two" in b
    assert "Report One" not in b
    assert "Mixed Linear Model Regression Results" in c