#!/usr/bin/env python3
"""Probe: does MixedLM's summary() honor the title argument?

Fits a small mixed-effects model, calls res.summary(title="Custom MixedLM
Summary"), and compares the returned report's title with the one that was
requested.

While the bug is present the returned title is the hardcoded default
("Mixed Linear Model Regression Results"), the requested title is ignored,
and the probe prints the observed mismatch and exits with status 1. After a
correct fix the title is honored, the probe prints an ok line and exits 0.

Run it against the INSTALLED statsmodels (the source tree at /app/src is not
importable by itself; see the task instruction):

    python3 /app/probe_title.py
"""
import numpy as np
import pandas as pd
from statsmodels.regression.mixed_linear_model import MixedLM

# 10 observations across 2 groups, 3 fixed-effect regressors (same toy model
# the project's own summary tests fit).
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

want = "Custom MixedLM Summary"
got = res.summary(title=want).title
print("requested title:", want)
print("returned title :", got)
default = res.summary().title
print("title with no argument:", default)

if got == want:
    print("ok: summary honors the title argument")
    raise SystemExit(0)

print("BUG PRESENT: the reported title argument was ignored and the default")
print("heading was printed instead")
raise SystemExit(1)