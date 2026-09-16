#!/usr/bin/env python3
"""Hidden case H2: python datetime.timedelta inputs the upstream test does not
use — an object-dtype numpy array of timedeltas, a timedelta list with bins
and range parameters, negative timedeltas, and a 2-D python list — must all
raise the clean explanatory TypeError from the histogram feature.
"""
import datetime
import sys

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt

CLEAN = "does not currently support timedelta inputs"

T0 = datetime.timedelta(seconds=0)
CASES = {
    "object array of timedeltas": __import__("numpy").array(
        [datetime.timedelta(seconds=1), T0 + datetime.timedelta(seconds=7)],
        dtype=object,
    ),
    "timedelta list with bins=4": (
        [T0 + datetime.timedelta(seconds=i) for i in range(4)],
        {"bins": 4},
    ),
    "timedelta list with bins and range": (
        [T0 + datetime.timedelta(seconds=i) for i in range(6)],
        {"bins": 3, "range": (1, 5)},
    ),
    "negative and positive timedeltas": [
        datetime.timedelta(seconds=-3),
        datetime.timedelta(seconds=-1),
        datetime.timedelta(seconds=2),
    ],
    "2-D python list of timedeltas": [
        [datetime.timedelta(seconds=i) for i in range(2)],
        [datetime.timedelta(seconds=i + 3) for i in range(2)],
    ],
}


def main():
    for name, spec in CASES.items():
        data, kwargs = (spec if isinstance(spec, tuple) else (spec, {}))
        fig, ax = plt.subplots()
        try:
            ax.hist(data, **kwargs)
            print(f"H2 PYTHON TIMEDELTA FAILED: {name} accepted without error")
            plt.close(fig)
            return 1
        except TypeError as exc:
            if CLEAN not in str(exc):
                print(f"H2 PYTHON TIMEDELTA FAILED: {name} opaque: {str(exc)[:130]}")
                plt.close(fig)
                return 1
        except Exception as exc:
            print(f"H2 PYTHON TIMEDELTA FAILED: {name} {type(exc).__name__}: {str(exc)[:130]}")
            plt.close(fig)
            return 1
        plt.close(fig)
    print("H2 PYTHON TIMEDELTA OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())