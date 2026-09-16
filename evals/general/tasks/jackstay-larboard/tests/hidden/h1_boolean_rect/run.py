#!/usr/bin/env python3
"""Hidden case h1: boolean specshow on a rectangular boolean matrix with a
dense checkerboard pattern (inputs the upstream image test does not use) must
attach a BoundaryNorm with boundaries [0, 0.5, 1], map values below 0.5 to
the first level and values above 0.5 to the last level, and draw a colourbar
whose ticks are exactly the two boolean levels.
"""
import os
import sys

tree = os.environ.get("LIBROSA_TREE", "/app/src")
sys.path.insert(0, tree)

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import BoundaryNorm

import librosa
import librosa.display

def main():
    data = np.zeros((21, 13), dtype=bool)
    data[::2, ::2] = True
    data[1::2, 1::2] = True  # checkerboard
    fig, ax = plt.subplots()
    img = librosa.display.specshow(data, ax=ax)
    norm = img.norm
    if not isinstance(norm, BoundaryNorm):
        print("H1 BOOLEAN RECT FAILED: norm is %s, expected BoundaryNorm" % type(norm).__name__)
        plt.close(fig)
        return 1
    boundaries = [float(b) for b in norm.boundaries]
    if boundaries != [0.0, 0.5, 1.0]:
        print("H1 BOOLEAN RECT FAILED: boundaries %r != [0.0, 0.5, 1.0]" % boundaries)
        plt.close(fig)
        return 1
    low = float(norm(0.25))
    high = float(norm(0.75))
    mid = float(norm(0.9))
    if low != 0.0 or high <= 0.0 or high != mid:
        print("H1 BOOLEAN RECT FAILED: mapping low=%s high=%s mid=%s" % (low, high, mid))
        plt.close(fig)
        return 1
    cb = fig.colorbar(img)
    ticks = [float(t) for t in cb.get_ticks()]
    plt.close(fig)
    if len(ticks) != 3 or not np.allclose(ticks, [0.0, 0.5, 1.0]):
        print("H1 BOOLEAN RECT FAILED: colourbar ticks %r != [0.0, 0.5, 1.0]" % ticks)
        return 1
    print("H1 BOOLEAN RECT OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())