#!/usr/bin/env python3
"""Hidden case h4: override semantics must be preserved. (a) When the caller
passes an explicit cmap for boolean data (bypassing colormap inference), the
continuous normaliser must remain — no BoundaryNorm may be injected. (b) When
the caller passes their own normaliser object, it must be used as-is
(setdefault must not clobber it).
"""
import os
import sys

tree = os.environ.get("LIBROSA_TREE", "/app/src")
sys.path.insert(0, tree)

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import BoundaryNorm, Normalize

import librosa
import librosa.display

def main():
    data = (np.random.default_rng(11).random((12, 12)) > 0.5)
    # (a) explicit colormap: no BoundaryNorm may appear
    fig, ax = plt.subplots()
    img = librosa.display.specshow(data, ax=ax, cmap="gray_r")
    norm_a = img.norm
    plt.close(fig)
    if isinstance(norm_a, BoundaryNorm):
        print("H4 OVERRIDE FAILED: explicit cmap case got BoundaryNorm")
        return 1
    # (b) caller-supplied normaliser object is preserved
    user_norm = Normalize(vmin=-1, vmax=1)
    fig, ax = plt.subplots()
    img = librosa.display.specshow(data, ax=ax, norm=user_norm)
    norm_b = img.norm
    plt.close(fig)
    if norm_b is not user_norm:
        print("H4 OVERRIDE FAILED: user normaliser was not preserved (%r)" % type(norm_b).__name__)
        return 1
    print("H4 OVERRIDE OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())