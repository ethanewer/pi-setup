#!/usr/bin/env python3
"""Hidden case H3: multi-dataset histogram calls. If ANY dataset is a
duration (numpy timedelta64 or python timedelta) — first, middle or last —
the call must raise the clean explanatory TypeError. All-numeric
multi-dataset calls must keep working and return one row of counts per
dataset.
"""
import datetime
import sys

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np

CLEAN = "does not currently support timedelta inputs"

BAD_CASES = {
    "first dataset timedelta64": [
        np.array([1, 2, 5, 7], dtype="timedelta64[D]"),
        [1.5, 2.5, 3.5, 4.5],
    ],
    "second dataset timedelta64": [
        [1.5, 2.5, 3.5, 4.5],
        np.array([1, 2, 5, 7], dtype="timedelta64[D]"),
    ],
    "middle dataset python timedelta": [
        [1.0, 2.0, 3.0, 4.0],
        [datetime.timedelta(seconds=i) for i in range(4)],
        [10.0, 11.0, 12.0],
    ],
    "all three datasets durations": [
        np.array([1, 2], dtype="timedelta64[D]"),
        np.array([3, 4], dtype="timedelta64[s]"),
        [datetime.timedelta(seconds=1), datetime.timedelta(seconds=2)],
    ],
}


def main():
    for name, datasets in BAD_CASES.items():
        fig, ax = plt.subplots()
        try:
            ax.hist(datasets)
            print(f"H3 MULTIDATASET FAILED: {name} accepted without error")
            plt.close(fig)
            return 1
        except TypeError as exc:
            if CLEAN not in str(exc):
                print(f"H3 MULTIDATASET FAILED: {name} opaque: {str(exc)[:130]}")
                plt.close(fig)
                return 1
        except Exception as exc:
            print(
                f"H3 MULTIDATASET FAILED: {name} {type(exc).__name__}: {str(exc)[:130]}"
            )
            plt.close(fig)
            return 1
        plt.close(fig)

    # all-numeric multi-dataset hist must keep working: two rows of counts
    fig, ax = plt.subplots()
    n, bins, patches = ax.hist([[1, 2, 2, 3], [4, 4, 5, 6]], bins=3)
    plt.close(fig)
    if n.shape != (2, 3) or int(n.sum()) != 8:
        print(f"H3 MULTIDATASET FAILED: numeric multi-dataset counts={list(n)}")
        return 1
    print("H3 MULTIDATASET OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())