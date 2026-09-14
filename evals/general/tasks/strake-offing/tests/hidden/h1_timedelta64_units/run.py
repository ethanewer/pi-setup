#!/usr/bin/env python3
"""Hidden case H1: numpy timedelta64 inputs in units, shapes and sizes the
upstream regression test does not use — seconds/milliseconds/microseconds,
a 2-D matrix, and a length-1 array — must all raise the clean explanatory
TypeError from the histogram feature.
"""
import sys

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np

CLEAN = "does not currently support timedelta inputs"

CASES = {
    "timedelta64[s]": np.array([0, 1, 2, 5, 8], dtype="timedelta64[s]"),
    "timedelta64[ms]": np.array([50, 150, 250, 400], dtype="timedelta64[ms]"),
    "timedelta64[us]": np.array([10, 20, 30, 40], dtype="timedelta64[us]"),
    "timedelta64[ns]": np.array([1, 2, 3], dtype="timedelta64[ns]"),
    "timedelta64 2-D (3,2)": np.array(
        [[1, 2], [3, 5], [7, 11]], dtype="timedelta64[D]"
    ),
    "timedelta64 length 1": np.array([9], dtype="timedelta64[D]"),
}


def main():
    for name, data in CASES.items():
        fig, ax = plt.subplots()
        try:
            ax.hist(data)
            print(f"H1 TIMEDELTA64 UNITS FAILED: {name} accepted without error")
            plt.close(fig)
            return 1
        except TypeError as exc:
            if CLEAN not in str(exc):
                print(f"H1 TIMEDELTA64 UNITS FAILED: {name} opaque: {str(exc)[:130]}")
                plt.close(fig)
                return 1
        except Exception as exc:
            print(f"H1 TIMEDELTA64 UNITS FAILED: {name} {type(exc).__name__}: {str(exc)[:130]}")
            plt.close(fig)
            return 1
        plt.close(fig)
    print("H1 TIMEDELTA64 UNITS OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())