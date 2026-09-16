#!/usr/bin/env python3
"""Hidden case for pintle-flint: cache=False on a multi-region 2-D image with
holes and float intensities.

The upstream regression test uses a small integer label map with several
blobs and reads one property. This case drives the same code path from a
2-D float image where regions are rings with holes (binary_fill_holes
matters), reads many properties per region (including 2-D-only ones such as
solidity, eccentricity and the major axis length, plus intensity-weighted
ones), and requires that cache=False retains nothing in ANY region. It also
verifies values agree with cache=True and that hole-filling measurements
(area_filled > area) are still reported correctly after the fix.
"""

import numpy as np

from skimage.measure import regionprops

# Three labelled regions, two of them rings (annuli) with a hole inside.
label = np.zeros((40, 40), dtype=int)
# ring 1: annulus centred at (row 10, col 10), outer radius 7, inner radius 3
# ring 2: annulus centred at (row 10, col 30), outer radius 6, inner radius 2
# disk 3: filled square (no hole)
yy, xx = np.mgrid[0:40, 0:40]
d1 = np.sqrt((xx - 10) ** 2 + (yy - 10) ** 2)
label[(d1 >= 3) & (d1 <= 7)] = 1
d2 = np.sqrt((xx - 30) ** 2 + (yy - 10) ** 2)
label[(d2 >= 2) & (d2 <= 6)] = 2
label[26:36, 4:14] = 3
assert len(np.unique(label)) == 4  # background + 3 labels

rng = np.random.default_rng(99)
intensity = rng.random(label.shape).astype(np.float64)
intensity[label == 1] *= 3.0
intensity[label == 2] *= 5.0

PROPS = (
    "area", "area_bbox", "bbox", "centroid",
    "area_convex", "image_convex", "equivalent_diameter_area",
    "euler_number", "extent", "area_filled", "image_filled",
    "solidity", "eccentricity", "orientation",
    "axis_major_length", "axis_minor_length", "perimeter",
    "moments", "moments_normalized", "inertia_tensor", "inertia_tensor_eigvals",
    "intensity_max", "intensity_mean", "intensity_std",
    "centroid_weighted", "centroid_local",
)


def val_close(a, b):
    """Tolerant equality that also treats NaNs as equal (allclose does not)."""
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    return np.allclose(a, b, rtol=1e-7, atol=1e-7, equal_nan=True)


off = regionprops(label, intensity_image=intensity, cache=False)
on = regionprops(label, intensity_image=intensity, cache=True)
assert len(off) == len(on) == 3

for r_off, r_on in zip(off, on):
    assert r_off.label == r_on.label
    before_keys = set(vars(r_off))
    for name in PROPS:
        v_off = getattr(r_off, name)
        v_on = getattr(r_on, name)
        ok = val_close(v_off, v_on)
        assert ok, "property %r of label %d differs between cache=False and cache=True" % (
            name, r_off.label,
        )
    assert r_off._cache == {}, (
        "cache=False retained %d properties for label %d" % (
            len(r_off._cache), r_off.label,
        )
    )
    # Name-agnostic retention check: cache=False must not store computed values
    # anywhere on the object, so no attribute may appear during the reads and a
    # second read must recompute (return a fresh object), like the fixed code.
    new_attrs = set(vars(r_off)) - before_keys
    assert not new_attrs, (
        "cache=False created retained attribute(s) %s for label %d" % (
            sorted(new_attrs), r_off.label,
        )
    )
    a = r_off.image_filled
    b = r_off.image_filled
    assert a is not b, (
        "cache=False second read returned the same object for label %d "
        "(values were retained, not recomputed)" % r_off.label
    )

# rings have holes: filled area must exceed the plain area for labels 1 and 2
by_label = {r.label: r for r in on}
assert by_label[1].area_filled > by_label[1].area, "ring 1 hole not filled"
assert by_label[2].area_filled > by_label[2].area, "ring 2 hole not filled"
assert by_label[3].area_filled == by_label[3].area, "disk has no hole"
# euler number of a ring is 0 (one component, one hole)
assert by_label[1].euler_number == 0 and by_label[2].euler_number == 0
assert by_label[3].euler_number == 1

# Positive control: cache=True still memoizes
r_on = on[0]
for name in ("area", "image", "image_filled", "inertia_tensor", "image_convex"):
    getattr(r_on, name)
assert r_on._cache, "cache=True should memoize properties but its stash is empty"

print("ok: case_holes_intensity — multi-region rings+disk, cache=False retains nothing, values agree")