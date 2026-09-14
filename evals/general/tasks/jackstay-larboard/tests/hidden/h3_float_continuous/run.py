#!/usr/bin/env python3
"""Hidden case h3: the boolean boundary-norm must fire ONLY for genuinely
boolean dtypes. Two-valued float input — both float64 in [0, 1] and a
float32 cast of a boolean array — must keep the normal continuous behaviour
(no BoundaryNorm). This guards the dtype-hardening in the fix: an agent that
over-applies the norm to any two-valued array breaks this case.
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
    rng = np.random.default_rng(3)
    cases = {
        "linspace_float64": np.linspace(0, 1, 24).reshape(6, 4),
        "bool_as_float64": (rng.random((9, 9)) > 0.5).astype(np.float64),
        "bool_as_float32": (rng.random((7, 7)) > 0.5).astype(np.float32),
    }
    for name, data in cases.items():
        fig, ax = plt.subplots()
        img = librosa.display.specshow(data, ax=ax)
        norm = img.norm
        plt.close(fig)
        if isinstance(norm, BoundaryNorm):
            print("H3 FLOAT CONTINUOUS FAILED: %s got %s" % (name, type(norm).__name__))
            return 1
    print("H3 FLOAT CONTINUOUS OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())