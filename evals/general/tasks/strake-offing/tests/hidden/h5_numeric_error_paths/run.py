#!/usr/bin/env python3
"""Hidden case H5: non-duration TypeErrors must keep their own error text.

The bugfix contract is that duration input fails fast with the explanatory
'does not currently support timedelta inputs' message AND that non-duration
inputs are completely unaffected.  A histogram call on plain numeric data
that is itself invalid (bad bins / bad range) raises a TypeError with a
dtype- and argument-specific message.  Those messages must survive the fix
unchanged: relabelling every TypeError inside the histogram feature as a
timedelta error would mask unrelated user errors, so the verifier rejects
any implementation whose non-duration TypeError text contains the timedelta
phrase.
"""
import sys

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np

CLEAN = "does not currently support timedelta inputs"

CASES = {
    "bins=object()": (
        lambda ax: ax.hist(np.ones(3), bins=object()),
        "must be an integer",
    ),
    "range=object()": (
        lambda ax: ax.hist(np.ones(3), range=object()),
        "cannot unpack non-iterable",
    ),
}


def main():
    for name, (call, expect_text) in CASES.items():
        fig, ax = plt.subplots()
        try:
            call(ax)
            print(f"H5 NUMERIC ERROR PATHS FAILED: {name} raised nothing")
            plt.close(fig)
            return 1
        except TypeError as exc:
            msg = str(exc)
            if CLEAN in msg:
                print(
                    f"H5 NUMERIC ERROR PATHS FAILED: {name} relabelled as a "
                    f"timedelta error: {msg[:120]}"
                )
                plt.close(fig)
                return 1
            if expect_text not in msg:
                print(
                    f"H5 NUMERIC ERROR PATHS FAILED: {name} lost its original "
                    f"message (got: {msg[:120]})"
                )
                plt.close(fig)
                return 1
        except Exception as exc:
            print(f"H5 NUMERIC ERROR PATHS FAILED: {name} "
                  f"{type(exc).__name__}: {str(exc)[:120]}")
            plt.close(fig)
            return 1
        plt.close(fig)
    print("H5 NUMERIC ERROR PATHS OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())