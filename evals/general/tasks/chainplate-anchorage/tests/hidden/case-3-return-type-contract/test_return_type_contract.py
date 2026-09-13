"""Hidden case 3 (chainplate-anchorage): the return-type contract.

For transforms whose two dimensions are not tracked separately (plain affine,
non-affine, identity, and composite transforms that do not contain a blend),
`contains_branch_seperately` must still return a PAIR OF BOOLEANS matching the
documented contract. The parent-commit base implementation returns a
two-element *list*; the result must be a tuple and its elements real bools,
and each element must equal the scalar `contains_branch` answer for that
transform. This guards the second half of the upstream fix (list -> tuple),
which the golden regression test alone does not exercise.
"""
import matplotlib
matplotlib.use('Agg')
import matplotlib.transforms as mtransforms
from matplotlib.transforms import Transform, Affine2D, IdentityTransform


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


def check(trf, other):
    res = trf.contains_branch_seperately(other)
    assert isinstance(res, tuple), \
        'contains_branch_seperately returned %s (%s), expected a tuple of bools' \
        % (type(res).__name__, res)
    assert len(res) == 2, 'expected exactly two elements, got %d' % len(res)
    assert all(isinstance(b, bool) for b in res), \
        'elements are not booleans: %r' % (res,)
    scalar = trf.contains_branch(other)
    assert res == (scalar, scalar), \
        'per-axis answer %r disagrees with scalar answer %r' % (res, scalar)
    return res


ta1 = Affine2D().rotate(3.14159 / 2)
ta1b = Affine2D().rotate(3.14159 / 2)   # value-equal to ta1
ta2 = Affine2D().translate(10, 0)
tn1 = NonAffineForTest(Affine2D().translate(1, 2))
tn2 = NonAffineForTest(Affine2D().translate(1, 2))
comp = ta1 + ta2

print('affine different :', check(ta1, ta2))
print('affine value-equal:', check(ta1, ta1b))
print('identity          :', check(IdentityTransform(), ta2))
print('non-affine        :', check(tn1, tn2))
print('composite         :', check(comp, ta2))

assert check(ta1, ta2) == (False, False)
assert check(ta1, ta1b) == (True, True)
assert check(IdentityTransform(), ta2) == (False, False)
assert check(tn1, tn2) == (False, False)
assert check(comp, ta2) == (False, False) or check(comp, ta2) == (True, True)

print('hidden case 3 ok')