#!/usr/bin/env python3
"""Hidden case h2: a wide, extremely sparse boolean matrix (only three True
cells out of 336) must still get the two-level boundary norm and a colourbar
with only the two boolean levels — same code path as h1, different shape and
sparsity.
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
    data = np.zeros((48, 7), dtype=bool)
    data[5, 3] = True
    data[40, 0] = True
    data[23, 6] = True
    fig, ax = plt.subplots()
    img = librosa.display.specshow(data, ax=ax)
    norm = img.norm
    if not isinstance(norm, BoundaryNorm):
        print("H2 BOOLEAN SPARSE FAILED: norm is %s, expected BoundaryNorm" % type(norm).__name__)
        plt.close(fig)
        return 1
    if [float(b) for b in norm.boundaries] != [0.0, 0.5, 1.0]:
        print("H2 BOOLEAN SPARSE FAILED: boundaries are wrong")
        plt.close(fig)
        return 1
    cb = fig.colorbar(img)
    ticks = [float(t) for t in cb.get_ticks()]
    plt.close(fig)
    if len(ticks) != 3 or not np.allclose(ticks, [0.0, 0.5, 1.0]):
        print("H2 BOOLEAN SPARSE FAILED: colourbar ticks %r != [0.0, 0.5, 1.0]" % ticks)
        return 1
    print("H2 BOOLEAN SPARSE OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())