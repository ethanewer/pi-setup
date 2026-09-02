# Repair the Onyx Forge telemetry platform

`/app` holds the working tree of the internally-built **Onyx Forge** telemetry
platform plus a few of its runtime components. The environment is deliberately
broken in several independent ways. Your job: **diagnose every break, repair
all of them in the live environment**, and hand back three artifacts:

- **`/app/repair.sh`** — a reusable, **idempotent** `bash` repair script.
- **`/app/env.txt`** — a conda environment spec (YAML) that names dependencies.
- **`/app/rebuilt/`** — a directory holding the freshly compiled C extension
  artifact (`*.so`) of the repaired package.

An external grader will later re-run every originally-failing check (some with
inputs you have not seen) and require that they all pass. It will also run your
`/app/repair.sh` from several different degraded states, so it must truly
**repair** each situation, not just special-case the current one.

You may hit the network; network access is **allowed** (corporate proxy is
already configured). `apt` and `pip` work against it. Work only under `/app`
and the system paths listed below.

## The four broken pieces + two artifacts

### 1. `onyxprism` (default-interpreter package)
The package currently installed in the default interpreter's site-packages is
only a broken stub that raises on `import onyxprism`. The **working, editable**
build is `/app/shelf/onyxprism` (a Cython extension plus a pure-python
reference). Rebuild and install it so the **system `python3`** (the default
interpreter) can import it with the **native** (compiled) backend:

```
python3 -c "import onyxprism; print(onyxprism.backend)"   # must print native
```

`onyxprism.checksum(data)` must equal `onyxprism._pure.checksum(data)` for any
input (the compiled Cython path and the pure-python reference must agree bit
for bit). `onyxprism.backend` must be the exact string `native` (i.e. the
compiled `_fast` extension actually loads under python3 — the import must NOT
degrade to the `fallback` backend).

### 2. Async filesystem unit suite
`/app/shelf/onyxprism/tests/test_async_fsdigest.py` is the package's **targeted
async-filesystem** unit suite (uses `asyncio` on the `onyxprism.fsdigest`
module). After the repair it must be green:

```
python3 -m pytest -q /app/shelf/onyxprism/tests
```

The suite must report `N passed`. It imports the installed `onyxprism`, so it
fails until the working build is installed.

### 3. pip is broken — restore it from the official bootstrap
The `pip` package and its launcher have been removed from the default
environment: `python3 -m pip` currently fails. **Do not rebuild pip from any
local/system copy.** Restore pip by fetching the **official bootstrap script**
from `https://bootstrap.pypa.io/get-pip.py` and running it with the default
interpreter. After that, `python3 -m pip --version` must succeed.

Then use the restored pip to **verify end-to-end that a fresh small package
installs and imports**: install the vendored helper `/app/shelf/prism`
(editable is fine) with the restored pip, so that `python3 -c "import prism"`
succeeds.

### 4. numpy importable system-wide
Later pipeline stages import `numpy`; it is not installed. Leave **numpy
importable from the default interpreter, globally**:

```
python3 -c "import numpy; print(numpy.__version__)"   # must not raise
```

(The extension does not itself need numpy; just make sure `import numpy` works
in the system python.)

### 5. conda environment from a dependencies spec
Create a new, **named** conda environment (`onyx_env`) **from a dependencies
spec**. Write that spec to `/app/env.txt` as conda YAML, then instantiate the
environment from it. The environment must be visible by name and usable:

```
/opt/miniconda/bin/conda env list                      # must show onyx_env
/opt/miniconda/bin/conda env create -f /app/env.txt -y # (from your spec)
/opt/miniconda/bin/conda run -n onyx_env python3 -c "print(1+1)"   # prints 2
```

The spec must include a `name:` of `onyx_env` and a pinned `python` version.
Choose a small, lean set of dependencies (a specific CPython version plus
`setuptools` is enough).

### 6. The `/app/rebuilt` deliverable
Running your repair must also compile the Cython extension and leave the
compiled artifact in **`/app/rebuilt/`** as a `_fast*.so` (the exact extension
module built for/native to the default interpreter). The grader will load that
`.so` directly from `/app/rebuilt` and check it computes `onyxprism.checksum`
correctly — it must agree with the pure reference for any input.

## Hidden / edge cases the grader will probe
After the repair the grader independently re-runs these (unseen) inputs and
states; your fix must generalize:

- `onyxprism.checksum(x)` vs `onyxprism._pure.checksum(x)` for many `x`,
  including the empty string, single characters, long repeated strings, and
  non-ASCII unicode (which is encoded as UTF-8).
- re-running `/app/repair.sh` after each of several degraded states: the
  compiled package gone, numpy uninstalled, the conda env missing, pip removed
  again, and `/app/rebuilt` deleted. Your repair script must re-fix each state
  and remain idempotent (safe to re-run).

## Rules
- Do **not** modify the source contents of `/app/shelf/onyxprism/*`'s algorithm
  files (`_fast.pyx`, `_pure.py`, `__init__.py`, `fsdigest.py`) or the tests;
  the only thing you may change there is nothing at all — install it as-is.
- `pip` must be restored from **`get-pip.py` only**, never from a hodgepodge of
  partially-removed files or an unrelated copy.
- Make `/app/repair.sh` idempotent: running it on an already-repaired container
  must exit `0`.
- Leave **both** deliverables plus every repaired-processed state in place when
  you are done.

Write concise diagnostics to stdout; the grader only cares about exit codes and
the final environment state.