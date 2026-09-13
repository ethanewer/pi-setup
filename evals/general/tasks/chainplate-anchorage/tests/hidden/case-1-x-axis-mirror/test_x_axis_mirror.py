"""Hidden case 1 (chainplate-anchorage): X-axis mirror of the upstream case.

The upstream regression test only covers the case where the *y* branch of a
blended transform inside a composite contains the other transform. This case
mirrors it on the *x* axis: `ss` sits inside the blend's x branch, not its y
branch. A correct per-axis answer for the composite is (True, False); the
parent-commit fallback reports both axes with the same whole-composite answer
(False, False) and fails this assertion.
"""
import matplotlib
matplotlib.use('Agg')
import matplotlib.transforms as mtransforms
from matplotlib.transforms import Transform, Affine2D


class NonAffineForTest(Transform):
    is_affine = False
    output_dims = 2
    input_dims = 2

    def __init__(self, real_trans, *a, **k):
        self.real_trans = real_trans
        super().__init__(*a, **k)

    def transform_non_affine(self, values):
        return self.real_trans.transform(values)

    def transform_path_non_affine(self, path):
        return self.real_trans.transform_path(path)


ta1 = Affine2D().rotate(3.14159 / 2)
ta2 = Affine2D().translate(10, 0)
ta3 = Affine2D().scale(1, 2)
tn1 = NonAffineForTest(Affine2D().translate(1, 2))
tn2 = NonAffineForTest(Affine2D().translate(1, 2))
tn3 = NonAffineForTest(Affine2D().translate(1, 2))
stack2 = ta1 + tn1 + ta2 + ta3
ss = tn1 + ta2 + ta3

# Sanity anchors the rest of the case on: the raw blend answers per-axis.
blend_x = mtransforms.BlendedGenericTransform(stack2, tn2)
x, y = blend_x.contains_branch_seperately(ss)
assert x is True and y is False, 'blend_x answered (%r, %r), expected (True, False)' % (x, y)

# The composite tn3 + blend_x must keep that per-axis answer.
comp = tn3 + blend_x
sx, sy = comp.contains_branch_seperately(ss)
print('blend_x =', x, y, ' composite =', sx, sy)
assert sx is True and sy is False, \
    'composite-of-blend answered (%r, %r), expected (True, False)' % (sx, sy)

print('hidden case 1 ok')