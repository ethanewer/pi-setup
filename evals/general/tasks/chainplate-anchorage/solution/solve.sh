#!/usr/bin/env bash
# Oracle for chainplate-anchorage: applies the minimal upstream fix to the
# matplotlib checkout at /app/src (CompositeGenericTransform must answer
# contains_branch_seperately per axis by delegating to its right-hand side,
# and the base Transform implementation must return a tuple of booleans, not
# a list), then proves the fix with the issue reproduction, the project's own
# regression test for this bug (golden bytes from the fix commit, baked at
# /opt/golden), and a subset of the project's own existing transform tests.
set -e

python3 /solution/fix_transforms.py /app/src/lib/matplotlib/transforms.py

echo "== issue reproduction: blended (F,T), composite+blend (F,T), tuple type =="
cd /app/src && python3 - <<'EOF'
import matplotlib; matplotlib.use('Agg')
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
blend = mtransforms.BlendedGenericTransform(tn2, stack2)
x, y = blend.contains_branch_seperately(ss)
sx, sy = (tn3 + blend).contains_branch_seperately(ss)
print('blend =', x, y, ' composite+blend =', sx, sy)
assert x is False and y is True and sx is False and sy is True
base = ta1.contains_branch_seperately(ta2)
print('base path type:', type(base).__name__, base)
assert isinstance(base, tuple) and base == (False, False)
print('ok')
EOF

echo "== golden regression test (fix-commit test_transforms.py, run from /tmp so the tree stays clean) =="
cd /app/src && cp /opt/golden/test_transforms.py /tmp/test_transforms_golden.py
python3 -m pytest \
  "/tmp/test_transforms_golden.py::TestBasicTransform::test_contains_branch" \
  -p no:cacheprovider -q

echo "== the project's own existing TestBasicTransform tests =="
cd /app/src/lib/matplotlib && cd tests && python3 -m pytest \
  "test_transforms.py::TestBasicTransform::test_transform_depth" \
  "test_transforms.py::TestBasicTransform::test_left_to_right_iteration" \
  "test_transforms.py::TestBasicTransform::test_transform_shortcuts" \
  "test_transforms.py::TestBasicTransform::test_contains_branch" \
  "test_transforms.py::TestBasicTransform::test_affine_simplification" \
  -p no:cacheprovider -q

echo "== deliverable: root-cause note =="
python3 - <<'EOF'
note = """Root cause

Transform.contains_branch_seperately(other) is documented to report, for the
x and y dimensions separately, whether `other` is contained in the transform's
tree. The base Transform implementation returns
`[self.contains_branch(other_transform)] * 2`: a two-element *list* whose
entries are both the whole-transform answer. That is the right value for
transforms whose two dimensions behave identically, but it is not the
documented pair-of-booleans return type, and CompositeGenericTransform had no
override, so a composite `left + right` whose right-hand side is a blended
(per-axis) transform answered both axes with the composite's whole-tree
answer. The y axis of the blended component genuinely contained the other
transform, but the composite reported (False, False) - code deciding e.g.
whether two axes share a y transform took the wrong branch and skipped work
such as data-limit updates.

Minimal change

`lib/matplotlib/transforms.py`, two hunks:
- CompositeGenericTransform gets a contains_branch_seperately override: the
  transform contains itself in both axes ((True, True)), otherwise the
  per-axis answer is delegated to the right-hand component (self._b), which
  know the axes separately.
- The base Transform.contains_branch_seperately now returns a tuple
  (self.contains_branch(other), ) * 2 instead of a list, matching the
  documented pair-of-booleans contract.
"""
open('/app/explanation.md', 'w', encoding='utf-8').write(note)
print('wrote /app/explanation.md')
EOF

echo "== oracle: all steps passed =="