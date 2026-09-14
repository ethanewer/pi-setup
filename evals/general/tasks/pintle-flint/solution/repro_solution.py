#!/usr/bin/env python3
"""Failing reproduction for the regionprops cache-retention bug (pintle-flint).

Deliverable contract (see instruction.md):

  * construct regions with cache=False, read several distinct properties
    (including at least one intensity property and one array-valued property),
  * inspect the region object's internal stash to count how many computed
    properties it is still holding,
  * print exactly one line `retained=<n>`,
  * exit 0 exactly when n == 0, non-zero when n > 0.

Against the buggy parent tree this exits non-zero (retained=3); against a
correct fix it prints retained=0 and exits 0.
"""

import sys

import numpy as np
from skimage.measure import regionprops

# A small labelled image with two blobs and a float intensity map.
label = np.zeros((24, 24), dtype=int)
label[3:10, 2:9] = 1
label[6:20, 14:21] = 2

rng = np.random.default_rng(7)
intensity = rng.random(label.shape)
intensity[label == 1] *= 2.0

# The labelled regions, with caching disabled.
regions = regionprops(label, intensity_image=intensity, cache=False)
if not regions:
    raise SystemExit("no regions found")

count = 0
for r in regions:
    # Read a spread of properties: array-valued (image_filled, inertia
    # tensor), scalar geometry (area, bbox), and intensity-weighted
    # (intensity_mean, intensity_std, intensity_max).
    _ = r.area
    _ = r.image_filled
    _ = r.bbox
    _ = r.inertia_tensor_eigvals
    _ = r.intensity_mean
    _ = r.intensity_std
    _ = r.intensity_max
    # Count how many computed properties this region object still holds.
    count += len(getattr(r, "_cache", {}))
    print(f"region {r.label}: retained={len(getattr(r, '_cache', {}))}")

print(f"retained={count}")
sys.exit(0 if count == 0 else 1)