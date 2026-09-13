# Fix a crash when printing optimizer results in SciPy

## Environment

You are working against the real upstream source tree of the SciPy
scientific-computing library, checked out at `/app/src`. The tree is a
development release of the project, complete with its own test suites under
`/app/src/scipy/**/tests/`. A compiled **dev install** of this exact tree is
active in the environment: `import scipy` loads the package built from
`/app/src` (the meson build directory is `/work/sci-build`; do not delete it).
NumPy, pytest and the rest of the build/test toolchain are installed. There is
**no network access** at trial time, and the machine is limited to **1 CPU**
(thread-pool limits are already set for you — do not raise them).

SciPy's source is the deliverable: **fix the bug in `/app/src`, not in the
installed site-packages copy**. Because the dev install maps the package's
text sources straight to the tree, edits you make to `.py` files under
`/app/src` are picked up by the running Python **immediately — no rebuild and
no reinstall step is needed**. The meson build directory `/work/sci-build`
holds the already-compiled extension modules; do not delete it and do not try
to rebuild the library (a from-scratch build costs tens of minutes and is not
required for your change).

## The bug

Optimizer functions in `scipy.optimize` (e.g. `scipy.optimize.minimize`,
`least_squares`, ...) return a result object that users conventionally display:
they print it, or a notebook cell just echoes the returned object. There is a
crash in the current source: **computing the repr of such a result object
raises `ValueError: max() iterable argument is empty` whenever one of its
fields holds an empty dict — for example an empty `options` map**, which is
exactly what many solvers return. Instead of showing the result, the user gets
a traceback. The same crash also happens when the empty dict is nested inside
another field of the result.

Reproduce it with the saved script at `/app/reproduce.py`:

```bash
python3 /app/reproduce.py
```

or the equivalent one-liner:

```bash
python3 - <<'EOF'
from scipy.optimize import OptimizeResult
print(repr(OptimizeResult(x=1, options={})))
EOF
```

## Task

Repair the source tree at `/app/src` so the crash is gone. Your fix must
satisfy:

1. Every result object of this kind must format without error, not just the
   one in the reproducer: an empty dict field **directly on the result**, an
   empty dict **nested inside another field's value**, and a result whose only
   field is an empty dict must all repr cleanly.
2. Non-empty dict fields must keep rendering their contents (e.g. a non-empty
   `options` map must still show its entries, such as `maxiter: 100`), and
   other fields (numbers, arrays, strings, bools) must display as before.
3. Do not modify SciPy's own test files or fixtures under
   `/app/src/scipy/**/tests/`. The verifier checks the integrity of the tree
   and runs the project's own regression and module suites against your
   repaired tree.
4. Leave the rest of the library untouched — `from scipy.optimize import
   OptimizeResult` and normal solvers must keep working.

The running package is your feedback loop: edit, re-run `/app/reproduce.py`
until it prints the result object, and use SciPy's own test suites (they are
in the tree, and pytest is installed) to make sure your change broke nothing
else. Do not spend time rebuilding the library — the dev install is already
built and your edits are live.

When you are done, `/app/src` must hold the repaired tree and
`/app/reproduce.py` must exit 0 printing a normal repr.