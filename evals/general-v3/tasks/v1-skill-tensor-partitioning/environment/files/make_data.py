#!/usr/bin/env python3
"""Generate a deterministic numeric tensor saved to /app/features.npy."""
import numpy as np

rng = np.random.default_rng(20240401)
tensor = rng.integers(0, 100, size=(64, 8), dtype=np.int64)
np.save("/app/features.npy", tensor)
print("saved", tensor.shape)