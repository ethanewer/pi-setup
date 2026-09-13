"""Hidden case 2 (chainplate-anchorage): deep composite nesting, and
self-containment.

The upstream regression test looks one level deep: `tn3 + blend`. Here the
blended transform is buried under TWO composite levels (`tn3 + (tn4 + blend)`),
and both of the blend's branches contain the other transform, so the correct
per-axis answer is (True, True). The parent-commit fallback collapses both
axes to the whole-composite subtree answer (False, False) and fails.

Also asserts the self-containment special case: every composite must report
(True, True) when asked whether it contains *itself* (the composite break-down
never yields the whole composite as a strict subtree pair, so this needs the
identity shortcut, not the delegation).
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
tn4 = NonAffineForTest(Affine2D().translate(3, 4))
stack2 = ta1 + tn1 + ta2 + ta3
ss = tn1 + ta2 + ta3

# blend2 contains ss on BOTH axes: x branch is stack2 (which contains ss,
# as the project's own test_contains_branch asserts), y branch is ss itself.
blend2 = mtransforms.BlendedGenericTransform(stack2, ss)
x, y = blend2.contains_branch_seperately(ss)
assert x is True and y is True, 'blend2 answered (%r, %r), expected (True, True)' % (x, y)

# Two composite levels on top: tn3 + (tn4 + blend2).
comp = tn3 + (tn4 + blend2)
sx, sy = comp.contains_branch_seperately(ss)
print('comp2 =', sx, sy)
assert sx is True and sy is True, \
    'two-level composite-of-blend answered (%r, %r), expected (True, True)' % (sx, sy)

# None of the components may be reported as contained when it is not.
assert comp.contains_branch_seperately(stack2 + ta3) == (False, False), \
    'composite wrongly reports an unrelated transform as contained'

# Self-containment: the composite contains itself in both axes.
assert comp.contains_branch_seperately(comp) == (True, True), \
    'composite does not report itself as contained'

print('hidden case 2 ok')