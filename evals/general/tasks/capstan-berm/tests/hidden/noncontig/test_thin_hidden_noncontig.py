"""Hidden case C (capstan-berm): thin() fed a NON-CONTIGUOUS boolean view
(strided, reversed-column, and transposed slices of a base array) must leave
the caller's array — including the base buffer the view aliases — untouched
and return the correct skeleton.

At the buggy parent commit the internal thinning buffer is created with
`np.asanyarray(image, dtype=bool).view(np.uint8)`, a memory-sharing view, so
deletion writes travel straight into the caller's buffer (and for a strided
view, into the base array it slices). These inputs exercise layouts the
upstream regression test never uses, so passing the golden test alone cannot
satisfy them.
"""
import numpy as np
from skimage.morphology import thin

# logical content of the strided view below (13x13), precomputed at authoring
STRIDED_SKELETON = np.array(
    [
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ],
    dtype=bool,
)

# logical content of the reversed-column view below (12x16)
REVERSED_SKELETON = np.array(
    [
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ],
    dtype=bool,
)

# logical content of the transposed view below (16x12)
TRANSPOSED_SKELETON = np.array(
    [
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ],
    dtype=bool,
)


def test_thin_strided_view_preserves_base_buffer():
    base = np.zeros((26, 26), dtype=bool)
    base[2:20, 4:22] = True
    base[20, 10] = True
    base[21, 10] = True
    base[22, 10] = True
    img = base[::2, ::2]  # 13x13 strided (non-contiguous) boolean view
    snapshot = base.copy()
    skeleton = thin(img)
    # the buffer the view aliases must be untouched...
    np.testing.assert_array_equal(base, snapshot)
    # ...so the view itself is untouched...
    np.testing.assert_array_equal(img, snapshot[::2, ::2])
    # ...and the skeleton is the exact thinning of the view's logical content
    np.testing.assert_array_equal(skeleton, STRIDED_SKELETON)


def test_thin_reversed_view_preserves_base():
    rev_base = np.zeros((12, 16), dtype=bool)
    rev_base[4:8, 4:12] = True
    img = rev_base[:, ::-1]  # columns reversed: negative-stride boolean view
    snapshot = rev_base.copy()
    skeleton = thin(img)
    np.testing.assert_array_equal(rev_base, snapshot)
    np.testing.assert_array_equal(img, snapshot[:, ::-1])
    np.testing.assert_array_equal(skeleton, REVERSED_SKELETON)


def test_thin_transposed_view_preserves_base():
    t = np.zeros((12, 16), dtype=bool)
    t[4:8, 4:12] = True
    img = t.T  # 16x12 Fortran-ordered boolean view
    snapshot = t.copy()
    skeleton = thin(img)
    np.testing.assert_array_equal(t, snapshot)
    np.testing.assert_array_equal(img, snapshot.T)
    np.testing.assert_array_equal(skeleton, TRANSPOSED_SKELETON)