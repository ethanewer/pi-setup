#!/usr/bin/env python3
"""Hidden case H4: numeric histogram behaviour must be completely unaffected
by the fix — bin counts for float/int input, the documented workaround for
durations (converting timedelta64 values to plain numbers first, e.g. via
.astype(np.float64) or .total_seconds()), and auto-binning all produce exact
results. Expected counts are computed with numpy's own histogram, which is
the ground truth for these plain (no weights/density) cases.
"""
import sys

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np


def hist_counts(data, bins):
    fig, ax = plt.subplots()
    try:
        n, b, p = ax.hist(data, bins=bins)
        return np.asarray(n)
    finally:
        plt.close(fig)


def main():
    # float array, auto-derived edges
    data = np.array([1.0, 2.0, 2.0, 7.0])
    got = hist_counts(data, 3)
    want = np.histogram(data, bins=3)[0]
    if not np.array_equal(got, want) or int(got.sum()) != 4:
        print(f"H4 NUMERIC UNAFFECTED FAILED: float counts={list(got)} want={list(want)}")
        return 1

    # int array, explicit bin edges
    data = np.array([3, 1, 4, 1, 5, 9, 2, 6])
    edges = [0, 3, 6, 10]
    got = hist_counts(data, edges)
    want = np.histogram(data, bins=edges)[0]
    if not np.array_equal(got, want):
        print(f"H4 NUMERIC UNAFFECTED FAILED: int counts={list(got)} want={list(want)}")
        return 1

    # documented workaround: convert durations to numbers, then histogram
    td = np.array([1, 2, 5, 7], dtype="timedelta64[D]")
    converted = td.astype(np.float64)
    got = hist_counts(converted, 3)
    want = np.histogram(converted, bins=3)[0]
    if not np.array_equal(got, want):
        print(f"H4 NUMERIC UNAFFECTED FAILED: converted counts={list(got)} want={list(want)}")
        return 1

    # auto-binning a numeric array must still succeed and keep every point
    data = np.linspace(0.0, 10.0, 101)
    got = hist_counts(data, "auto")
    if int(got.sum()) != 101:
        print(f"H4 NUMERIC UNAFFECTED FAILED: auto-bin counts sum={int(got.sum())}")
        return 1

    print("H4 NUMERIC UNAFFECTED OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())