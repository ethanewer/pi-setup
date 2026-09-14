#!/usr/bin/env python3
"""Hidden case for pintle-flint: cache=False on a 3-D volume.

The upstream regression test uses a 2-D integer label map and reads a single
property (image_filled). This case drives the same _cached code path from a
3-D volumetric label map with two labelled blobs and a float intensity volume,
reads a spread of properties (including 3-D-only and intensity-weighted ones),
and requires that with cache=False the region object retains NONE of them.
It also checks value-for-value agreement with cache=True regions and that
cache=True still memoizes (positive control), so a "fix" that disables caching
altogether cannot pass.
"""

import numpy as np

from skimage.measure import regionprops

rng = np.random.default_rng(1234)
label = np.zeros((10, 12, 14), dtype=int)
label[1:5, 2:7, 3:8] = 1        # first 3-D blob
label[6:10, 8:12, 9:14] = 2     # second 3-D blob
assert len(np.unique(label)) == 3

intensity = rng.random(label.shape)
intensity[label == 1] += 1.0
intensity[label == 2] += 2.0

PROPS = (
    "area", "area_bbox", "bbox", "centroid", "coords",
    "equivalent_diameter_area", "euler_number", "extent",
    "area_filled", "image_filled", "image", "image_convex", "area_convex",
    "inertia_tensor", "inertia_tensor_eigvals",
    "moments", "moments_normalized", "moments_central",
    "intensity_max", "intensity_mean", "intensity_std",
    "centroid_weighted", "moments_weighted_central", "centroid_local",
)


def val_close(a, b):
    """Tolerant equality that also treats NaNs as equal (allclose does not)."""
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    return np.allclose(a, b, rtol=1e-7, atol=1e-7, equal_nan=True)


# cache=False: nothing may be retained, values must match the cached run.
off = regionprops(label, intensity_image=intensity, cache=False)
on = regionprops(label, intensity_image=intensity, cache=True)
assert len(off) == len(on) == 2
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
        "cache=False retained %d properties for 3-D label %d" % (
            len(r_off._cache), r_off.label,
        )
    )
    # Name-agnostic retention check (see case_holes_intensity): nothing may be
    # retained anywhere on the object and a second read must be recomputed.
    new_attrs = set(vars(r_off)) - before_keys
    assert not new_attrs, (
        "cache=False created retained attribute(s) %s for 3-D label %d" % (
            sorted(new_attrs), r_off.label,
        )
    )
    a = r_off.image_filled
    b = r_off.image_filled
    assert a is not b, (
        "cache=False second read returned the same object for 3-D label %d "
        "(values were retained, not recomputed)" % r_off.label
    )

# Positive control: with cache=True the same properties ARE memoized.
r_on = on[0]
for name in ("area", "image", "image_filled", "inertia_tensor", "image_convex"):
    getattr(r_on, name)
assert r_on._cache, "cache=True should memoize properties but its stash is empty"
first = r_on.image_filled
assert "image_filled" in r_on._cache
assert r_on.image_filled is first or np.array_equal(r_on.image_filled, first)
# exact value sanity for one 3-D scalar quantity
assert off[0].area == np.sum(label[1:5, 2:7, 3:8] == 1) * 1.0

print("ok: case_threed — 3-D volume, cache=False retains nothing, values agree, cache=True memoizes")