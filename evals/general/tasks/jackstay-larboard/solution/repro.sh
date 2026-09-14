#!/usr/bin/env python3
"""The task's reproduction script — this is the ORACLE's version, installed at
/app/repro.sh by the oracle. The agent writes an equivalent script before
fixing anything; the verifier runs the agent's script, not this one.

Contract (same for the oracle's copy and the agent's):
  * honors $LIBROSA_TREE (a directory whose 'librosa' package is used);
    defaults to /app/src.
  * plots a boolean 2D array with the library's spectrogram-style heatmap
    function and checks the normaliser attached to the returned image.
  * prints a short diagnosis line to stdout and exits 0 if and only if boolean
    data renders with a two-level boundary normaliser (colourbar shows only the
    two extremes), exits nonzero otherwise (bug present).
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

rng = np.random.default_rng(1234)
data = rng.random((8, 8)) > 0.5

fig, ax = plt.subplots()
try:
    img = librosa.display.specshow(data, ax=ax)
    norm = img.norm
    if isinstance(norm, BoundaryNorm) and [float(b) for b in norm.boundaries] == [0.0, 0.5, 1.0]:
        print("BOOLEAN COLOURBAR OK: two-level BoundaryNorm([0, 0.5, 1]) attached")
        sys.exit(0)
    print("BUG PRESENT: boolean specshow got", type(norm).__name__, "instead of BoundaryNorm([0, 0.5, 1])")
    sys.exit(1)
finally:
    plt.close(fig)