# Setting an explicit numeric offset of 1 on the scalar tick formatter is ignored

## Situation

`/app/src` is a shallow clone of the matplotlib repository
(`https://github.com/matplotlib/matplotlib`) at upstream commit
`91d115ec161286b70da1447f53844b909247741f`, checked out in detached HEAD. The
library is already built and installed from that checkout in editable mode,
so `import matplotlib` resolves to `/app/src/lib/matplotlib`, and any edit you
make under `/app/src/lib` is live immediately — no rebuild, no reinstall step.

There is **no network** at trial time: `git fetch`, `curl`, `pip install` and
any other network use will fail.

The project's unit tests live under `/app/src/lib/matplotlib/tests` and run
with pytest. Only run targeted tests: some modules in the suite contain slow,
flaky image-comparison tests.

## The bug

matplotlib's scalar axis tick formatter supports "offset notation": when the
tick values are large compared to their range, the axis is labelled with the
small residual numbers plus a single additive constant (the offset) written at
the edge of the axis. The formatter exposes a setter, documented as accepting
either a boolean or a number:

- `False` — never use offset notation;
- `True` — automatic mode: use offset notation only when it meaningfully
  shortens the labels;
- a number — force offset notation with exactly that offset.

Everything works as documented except for one specific numeric value. Passing
`1` as a forced numeric offset does not force an offset of 1. Instead of
writing tick labels relative to +1, matplotlib silently switches the formatter
into automatic offset mode and resets the offset to zero — exactly as if the
boolean `True` had been passed.

Here is the issue's own reproduction; it fails:

```
python3 - <<'EOF'
import matplotlib
matplotlib.use('Agg')
from matplotlib.ticker import ScalarFormatter
f = ScalarFormatter()
f.set_useOffset(1)
print('offset =', repr(f.offset), ' useOffset =', repr(f.get_useOffset()))
assert f.offset == 1 and f.get_useOffset() is False
EOF
```

The assert raises. On this image the printed line reads
`offset = 0  useOffset = 1`: the formatter stored a zero offset and
`get_useOffset()` returns a truthy value (the number `1`), i.e. it ended up
in automatic mode exactly as if `True` had been passed.

## What to do

Fix the library in the checked-out tree at `/app/src` so that a numeric
offset of `1` is treated as a number, exactly like `2` or `1000`, and only
actual boolean values toggle offset mode on or off. When you are done:

- The reproduction above must print `offset = 1 useOffset = False` and pass.
- `set_useOffset(0)`, `set_useOffset(1.5)`, `set_useOffset(1000)` and any other
  numeric value must behave numerically: the offset is stored as given and
  automatic mode is off.
- `set_useOffset(True)` and `set_useOffset(False)` must keep exactly their
  documented behaviour: automatic mode on / off, offset reset to 0.
- The project's own existing tests for this formatter must keep passing. They
  live in `lib/matplotlib/tests/test_ticker.py`; for example run

  ```
  cd /app/src && python3 -m pytest \
    lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_use_offset \
    lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_set_use_offset_float \
    -q
  ```

  (Pick the node ids you consider relevant — the point is to exercise the
  project's own tests, not to invent new ones.)

Write a short root-cause note to `/app/explanation.md`: what the documented
API contract is, what went wrong specifically for the value 1, and the minimal
change you made. A few sentences are enough.

Do not change the git metadata of the checkout (no new commits, no rebasing,
no `git checkout` of other revisions): the tree must remain the same clone of
the same revision, with only the code fix applied to your working tree. And do
not touch anything under `/solution` or `/tests`: those belong to the
verifier, which runs its own checks against your fixed tree. The deliverables
are the fixed repository at `/app/src` and the note at `/app/explanation.md`.