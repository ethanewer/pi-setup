#!/usr/bin/env python3
"""Generate a DNA string whose G+C composition stays inside a stated
percentage range in every contiguous sliding window of a fixed length.

Contract:
    python3 /app/window.py <out_path> <length> <window> <gc_min> <gc_max>

Writes exactly `length` nucleotides (only A, C, G, T) to <out_path> as a single
line followed by a trailing newline (no other whitespace). For EVERY contiguous
window of length <window> the percentage of G+C nucleotides must lie within
[gc_min, gc_max] inclusive. The provided inputs are guaranteed to admit a
feasible integer count k of G/C per window (i.e. ceil(gc_min%*W/100) <=
floor(gc_max%*W/100)). Exit status 0 on success.
"""

import sys


import math


def generate(length, window, gc_min, gc_max):
    """Return a DNA string of length `length` satisfying the window GC bound."""
    # Number of G/C nucleotides per window that make k/W*100 in [gc_min,gc_max].
    lo = max(0, int(math.ceil(gc_min * window / 100.0)))   # ceil(min%*W/100)
    hi = min(window, int(math.floor(gc_max * window / 100.0)))  # floor(max%*W/100)
    k = hi if hi >= lo else lo

    # Build one window-width period holding exactly k G/C, spread evenly,
    # with the remaining (window-k) positions alternating A/T.
    period = ["A"] * window
    if window > 0 and k > 0:
        step = window / k
        gcs = [int(i * step) for i in range(k)]
        for n, idx in enumerate(gcs):
            period[idx] = "G" if n % 2 == 0 else "C"
    # fill non-GC cells with a balanced A/T pattern
    at = ["A", "T"]
    j = 0
    for i in range(window):
        if period[i] == "A":
            period[i] = at[j % 2]
            j += 1

    # Tile the period up to `length`. Because the period length equals the
    # window length, every length-`window` contiguous substring is a rotation
    # of the period and contains exactly k G/C => always inside the range.
    out = []
    i = 0
    while len(out) < length:
        out.append(period[i % window])
        i += 1
    return "".join(out)


def main(argv):
    if len(argv) != 6:
        sys.stderr.write(
            "usage: window.py <out_path> <length> <window> <gc_min> <gc_max>\n")
        return 2
    out_path = argv[1]
    length = int(argv[2])
    window = int(argv[3])
    gc_min = float(argv[4])
    gc_max = float(argv[5])
    if window <= 0 or length <= 0:
        sys.stderr.write("length and window must be positive\n")
        return 2
    seq = generate(length, window, gc_min, gc_max)
    with open(out_path, "w") as fh:
        fh.write(seq + "\n")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main(sys.argv))