#!/usr/bin/env python3
"""Oracle fix for strake-offing: add the upstream input guard to Axes.hist.

Inserts the exact block added by upstream commit
c72236701f0371d37c8a3232133347d5b350bc59 into the histogram function in
lib/matplotlib/axes/_axes.py, immediately after the input is reshaped to a
list of datasets and before unit processing / binning. Fails loudly if the
working tree is not exactly at the pinned parent commit.
"""
import pathlib
import sys

TARGET = pathlib.Path("/app/src/lib/matplotlib/axes/_axes.py")

# The two lines that precede the insertion point in the parent tree.
needle = (
    "        x = cbook._reshape_2D(x, 'x')\n"
    "        nx = len(x)  # number of datasets\n"
)

# The exact upstream inserted block (message text, spacing and all).
block = (
    "\n"
    "        for arr in x:\n"
    "            if len(arr) > 0 and isinstance(\n"
    "                arr[0], (datetime.timedelta, np.timedelta64)\n"
    "            ):\n"
    "                raise TypeError(\n"
    '                    "Axes.hist does not currently support timedelta inputs. "\n'
    '                    "Convert to numeric values  (e.g., .total_seconds()) first."\n'
    "                )\n"
)

src = TARGET.read_text(encoding="utf-8")
n = src.count(needle)
if n != 1:
    print(f"oracle: expected exactly one insertion point, found {n}; aborting", file=sys.stderr)
    sys.exit(1)
if "does not currently support timedelta inputs" in src:
    print("oracle: fix already present; nothing to do")
    sys.exit(0)

patched = src.replace(needle, needle + block)
compile(patched, str(TARGET), "exec")  # must parse
TARGET.write_text(patched, encoding="utf-8")
print("oracle: inserted the timedelta input guard into Axes.hist")