#!/usr/bin/env python3
"""Body of the strake-offing reproduction.

Imports matplotlib from whichever copy the surrounding environment resolves
(repro.sh sets up MPL_TREE and, for /opt/prefix, the editable-hook skip
variables) and asserts that the histogram feature rejects duration inputs
(numpy timedelta64 array, python datetime.timedelta list) with the clean
explanatory TypeError whose message contains "does not currently support
timedelta inputs", and that numeric binning still returns correct counts.
Exits 0 iff every check holds; prints a one-line diagnosis otherwise.
"""
import datetime
import sys

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np

DURATION_CASES = {
    "numpy timedelta64[D]": np.array([1, 2, 5, 7], dtype="timedelta64[D]"),
    "python datetime.timedelta list": [
        datetime.timedelta(seconds=i) for i in range(5)
    ],
}

CLEAN = "does not currently support timedelta inputs"


def main():
    failures = []
    for name, data in DURATION_CASES.items():
        fig, ax = plt.subplots()
        try:
            ax.hist(data)
            failures.append(f"{name}: hist ACCEPTED duration input (no error raised)")
        except TypeError as exc:
            if CLEAN not in str(exc):
                failures.append(
                    f"{name}: raised an opaque TypeError: {str(exc)[:140]}"
                )
        except Exception as exc:
            failures.append(
                f"{name}: raised an opaque {type(exc).__name__}: {str(exc)[:140]}"
            )
        finally:
            plt.close(fig)

    # numeric sanity: binning a small float array must still work
    fig, ax = plt.subplots()
    try:
        counts, bins, patches = ax.hist(np.array([1.0, 2.0, 5.0, 7.0]), bins=3)
    finally:
        plt.close(fig)
    if not (len(counts) == 3 and int(counts.sum()) == 4):
        failures.append(f"numeric hist sanity failed: counts={list(counts)}")

    if failures:
        print("\n".join(failures))
        return 1
    print(
        "hist rejects timedelta64 and datetime.timedelta input with the "
        "explanatory TypeError; numeric histogram intact"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())