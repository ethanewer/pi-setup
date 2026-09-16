# Per-axis transform containment reports the wrong answer for composite transforms

## Situation

`/app/src` is a shallow clone of the matplotlib repository
(`https://github.com/matplotlib/matplotlib`) at upstream commit
`74c7f9a598c4e32b3f551f75ed965f446d786ab1`, checked out in detached HEAD. The
library is already built and installed from that checkout in editable mode,
so `import matplotlib` resolves to `/app/src/lib/matplotlib`, and any edit
you make under `/app/src/lib` is live immediately — no rebuild, no reinstall
step.

There is **no network** at trial time: `git fetch`, `curl`, `pip install`
and any other network use will fail.

The project's unit tests live under `/app/src/lib/matplotlib/tests` and run
with pytest. Only run targeted tests: some modules in the suite contain slow,
flaky image-comparison tests.

## The bug

matplotlib's transform framework (`matplotlib.transforms`) has a method
`Transform.contains_branch_seperately(other)` whose documented contract is to
report whether `other` is contained in this transform's tree **separately for
the x and y dimensions** — a pair of booleans `(x_contains, y_contains)`.

That answer is wrong for one class of transforms. When the transform is a
*composite* — the composition of a left and a right transform, written
`left + right` — whose right-hand component is itself a *blended* (per-axis)
transform, the method reports **both** dimensions as not contained even when
one dimension genuinely is contained. Whatever the y axis of the blended
component contains, the composite claims to contain nothing at all. Library
code that relies on the per-axis answer to decide, for example, whether two
axes share the same y transform then takes the wrong branch.

On top of that, for ordinary (non-blended, non-composite) transforms the
method returns a Python **list** `[result, result]` where the documented
return type is a pair of booleans. The return type must match the contract
too.

Here is a reproduction; on this image it currently fails:

```python
python3 - <<'EOF'
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
print("blend =", x, y, " composite+blend =", sx, sy)
assert x is False and y is True and sx is False and sy is True
EOF
```

The blended transform answers correctly: `(False, True)` — its y branch
contains `ss`. The composite `tn3 + blend` must answer the same way (its y
dimension passes straight through the blended component), but on this tree it
answers `(False, False)`, and the assert raises.

## What to do

Fix the library in the checked-out tree at `/app/src` so the per-axis
containment answers and their return type match the documented contract:

- For every transform, `contains_branch_seperately(other)` must return a pair
  of booleans `(x_contains, y_contains)` — not a list.
- A composite transform `left + right` must look through its own composition
  when answering per-axis containment: any dimension that the right-hand side
  of the composition reports as contained must be reported as contained by
  the composite (and any dimension the right-hand side does not contain must
  not be reported as contained just because a non-blended fallback would lump
  both dimensions together).
- When the composite transform is asked whether it contains **itself**, both
  components are trivially contained: `(True, True)`.
- Blended transforms (`BlendedGenericTransform`) already answer correctly and
  must keep doing so.
- The reproduction above must pass: it must print
  `blend = False True  composite+blend = False True` and exit 0.
- The project's own existing transform tests must keep passing. They live in
  `lib/matplotlib/tests/test_transforms.py`; for example run

  ```
  cd /app/src && python3 -m pytest \
    lib/matplotlib/tests/test_transforms.py::TestBasicTransform::test_contains_branch \
    lib/matplotlib/tests/test_transforms.py::TestBasicTransform::test_affine_simplification \
    -q
  ```

  (Pick the node ids you consider relevant — the point is to exercise the
  project's own tests, not to invent new ones.)

Write a short root-cause note to `/app/explanation.md`: what the documented
per-axis contract is, what the composite transform's fallback implementation
did wrong, and the minimal change you made. A few sentences are enough.

Do not change the git metadata of the checkout (no new commits, no rebasing,
no `git checkout` of other revisions): the tree must remain the same clone of
the same revision, with only the code fix applied to your working tree. And
do not touch anything under `/solution` or `/tests`: those belong to the
verifier, which runs its own checks against your fixed tree. The deliverables
are the fixed repository at `/app/src` and the note at `/app/explanation.md`.