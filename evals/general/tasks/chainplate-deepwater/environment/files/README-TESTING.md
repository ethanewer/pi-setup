# Testing machinery in this image

Everything below runs offline; the container has no network.

## The two code copies and their relationship

- `/app/src` is the real upstream source tree (a shallow, detached clone of a
  single pinned commit). **This is the code you must fix.**
- `/app/env` is a Python virtual environment with pinned dependencies:
  `torch==2.10.0+cpu` and `torchvision==0.25.0+cpu` (plus `pytest`).
  The installed `torchvision` package is *not* the released wheel as-is: the
  pure-Python `transforms/v2` and `tv_tensors` packages were replaced at
  image-build time with the exact bytes of the checkout, so the installed
  package runs precisely the code that is checked out in `/app/src`. (The
  wheel predates the pinned commit — it does not even have all the names the
  project's own test modules import — which is why the mirror exists.)

When you change a module inside `/app/src`, the installed package does **not**
see it until you refresh the mirror: copy the file to the same relative path
under your venv's `site-packages`:

```bash
cp /app/src/torchvision/transforms/v2/functional/<file>.py \
   /app/env/lib/python3.12/site-packages/torchvision/transforms/v2/functional/<file>.py
```

The working python for everything below is `/app/env/bin/python`.

### Bytecode caches

Python compiles imported modules to `__pycache__/*.pyc`. After refreshing the
mirror, clear the cached bytecode so the interpreter cannot trust a stale
`.pyc` (source files hold their mtimes; overwriting a file of the same size in
the same second can otherwise leave stale bytecode around):

```bash
find /app/env/lib/python3.12/site-packages/torchvision -name __pycache__ -type d -exec rm -rf {} +
```

## Reproducing

```bash
/app/env/bin/python /opt/repro.py
```

## Running the project's own test suite

The upstream regression test for this bug ships in the image at
`/opt/golden/test_transforms_v2.py` (it is exactly the project's own
`test/test_transforms_v2.py` from the fixed revision — the only difference from
what is checked out is the added non-regression test). To run it against your
working tree, plant it and run pytest with the venv:

```bash
cp /opt/golden/test_transforms_v2.py /app/src/test/test_transforms_v2.py
```

**Run pytest from a neutral working directory with an absolute test path.**
If you run it from inside `/app/src`, Python puts `/app/src` first on
`sys.path` and `import torchvision` silently resolves to the un-built source
tree instead of the installed package you fixed — tests then exercise the
wrong code. The working invocation:

```bash
cd /tmp
/app/env/bin/python -m pytest /app/src/test/test_transforms_v2.py \
    -k test_cxcywh_to_xyxy_odd_dimensions -o addopts='' -p no:cacheprovider
```

The repository's own `pytest.ini` turns warnings into errors; a wheel-pinned
venv trips those, so the working invocation disables the inherited `addopts`
and the on-disk cache (the project's own runner is still pytest on the
project's own test file — only the flags differ).

For the surrounding suite, run the whole regression class:

```bash
cd /tmp
/app/env/bin/python -m pytest /app/src/test/test_transforms_v2.py \
    -k "TestConvertBoundingBoxFormat" -o addopts='' -p no:cacheprovider -q
```

This is the project's own suite for this code path and it checks results
against the independently-maintained `torchvision.ops.box_convert` reference.

## Handy invariants while you work

- The HEAD of `/app/src` is pinned; do not commit, fetch or rewrite history.
- The working tree must end up differing from the pinned commit in **exactly
  one tracked source file** — the one your fix needs. Any planted test copies
  or scratch files must be removed from `/app/src` before you finish (put
  scratch in `/tmp`).
- `/app/env` must end up mirroring your fixed source (refresh after editing,
  purge bytecode caches).
- A single vCPU is available; keep numeric thread counts at 1 (already set via
  environment variables).

## Deliverables

1. `/app/src` — the repaired tree (one modified file, tree otherwise
   byte-identical to the pinned commit, no extra files).
2. `/app/env` — the installed package refreshed so it runs your fixed code.
3. `/app/summary.md` — your change summary (see the instructions file).