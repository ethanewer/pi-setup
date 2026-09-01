# Repair the Hailshot filesystem-analysis platform

`/app` holds the working tree of an internally-built async filesystem analysis
toolkit ("Hailshot") together with its runtime components. The **default
interpreter** (`/usr/bin/python3`) environment is deliberately broken in
several independent ways. Your job: **diagnose and repair every one of them**,
leave the environment fixed, and hand back three artifacts. An external grader
will re-run the broken commands after you and detect any that are still broken.

There is network access through the sandbox's package proxies (PyPI, the
Anaconda repo, and `bootstrap.pypa.io` are all reachable), so you may download
the official bootstrap script and packages. Work only under `/app` and the
system paths listed below.

## Deliverables — create exactly these files

1. **`/app/repair.sh`** — a `bash` script that applies every repair. It must be
   **idempotent** (safe to re-run; each step guards on whether it is already
   done) and exit `0` when re-run on an already-repaired container. Running it
   must leave every check in "What success looks like" passing.
2. **`/app/env.txt`** — a single line naming the conda environment you create
   from the dependencies spec (see item 5).
3. **`/app/rebuilt/`** — a directory holding the rebuilt compiled native
   extension for `hailshot` (a copy of the built `_native*.so`) plus a short
   `report.txt`.

You must **also apply the repairs to the live environment now** (run
`/app/repair.sh`), not merely leave a script behind.

## The broken components

### 1. pip is broken in the default interpreter
`python3 -m pip` reports `No module named pip`, and the bootstrap machinery
(`python3 -m ensurepip`) is gone too. Restore pip **from the official bootstrap
script** (`https://bootstrap.pypa.io/get-pip.py`) rather than from a locally
present broken copy. After this, `python3 -m pip --version` must print a
version.

### 2. The `hailshot` package cannot be installed/imported on the default interpreter
`/app/hailshot-src/` is the working source tree. Its **legacy `setup.py`**
still uses the `numpy.distutils` entry point, which was removed in the numpy
2.x installed on this image, so a straight `pip install` or `build_ext` fails.
Port the build to a modern `setuptools` + `Cython.Build.cythonize`
configuration, compile the Cython extension against the installed numpy, and
**reinstall the edited tree in editable mode** so the default interpreter can
import the **compiled** binary extension:

```
python3 -m pip install -e /app/hailshot-src --no-build-isolation
```

After this, all of these must hold:

```
python3 -c "import hailshot; print(hailshot._native.__file__)"  # ends in .so
python3 -c "import hailshot; print(hailshot.fingerprint('/etc/hostname'))"
python3 -m pytest -q /app/hailshot-src/tests                  # N passed
```

`hailshot.fingerprint(path)` computes an FNV-1a (32-bit) hash:
`h = 0x811c9dc5`; for each byte `b`: `h ^= b; h = (h * 0x01000193) & 0xFFFFFFFF`;
return `h`. The compiled extension (`hailshot._native`) and the pure-python
fallback (`hailshot._fallback`) implement the **same** algorithm, so they must
agree bit-for-bit on any file.

### 3. Verify package installation end-to-end through pip
With pip restored, install a small third-party package into the **default**
environment and import it successfully (any small pure-python package works,
e.g. `colorama`). The grader checks that a fresh `import <pkg>` succeeds.

### 4. Leave numpy importable
The later tests import numpy. Ensure `python3 -c "import numpy; print(numpy.__version__)"`
works on the default interpreter and that the version starts with `2.`.

### 5. Create a named conda environment from a dependencies spec
`/app/conda/environment.yml` is the dependencies spec. Create the environment
it names (a fresh `conda env create -f /app/conda/environment.yml`). The
environment's name must be written to `/app/env.txt`. The grader checks that
the environment exists (`conda env list`) and that
`conda run -n <name> python -c "import itsdangerous"` succeeds.

### 6. Make OSMesa discoverable for the interpreter
`/app/gloss/peregrine.py` is the offscreen-GL loader used by the platform. It
searches only the directory list from the `$HAILSHOT_GL_LIB` env var (colon
separated, empty entries dropped) **then** the fixed directory
`/opt/hailshot/gl/lib`, looking for `libOSMesa.so`, `libOSMesa.so.8`, or
`libOSMesa.so.6`. It never falls back to `ldconfig`. In the current image
`/opt/hailshot/gl/lib` is empty and `$HAILSHOT_GL_LIB` is unset. Place the
system OSMesa runtime library where the loader looks: the system library
`libOSMesa.so.8` already exists under `/usr/lib` (the `libosmesa6` package is
installed). Copy/symlink it to `/opt/hailshot/gl/lib/libOSMesa.so`. The loader
must also behave when `$HAILSHOT_GL_LIB` points at bogus/nonexistent
directories — those entries are skipped and loading still succeeds from the
fixed directory. On success the loader prints `HAILSHOT_GL_OK` and exits 0:

```
python3 /app/gloss/peregrine.py        # -> HAILSHOT_GL_OK
```

## Hidden / edge cases the grader will probe

After the repair the grader independently checks (you have not seen these but
your implementation must support them generally):

- `hailshot.fingerprint` (native **and** fallback mode) on files of size `0`,
  `1`, `65535`, `65536`, `65537`, and a few larger/varied ones — including
  exact chunk-boundary crossings — and asserts the two modes agree and match
  an independent FNV-1a computation;
- `hailshot.profile` / `hailshot.sweep` on a **hidden nested directory tree**
  (multiple levels, several files), where the native fingerprints, the file
  count, and the aggregate digest must match an independent computation;
- `python3 /app/gloss/peregrine.py` with `HAILSHOT_GL_LIB` set to bogus
  directories (must still load and print `HAILSHOT_GL_OK`);
- the conda env (from `/app/env.txt`) exists and can `import itsdangerous`.

Your implementations must be **general**, not hard-coded, for these inputs.

## Rules

- Do not modify `/app/gloss/peregrine.py`, the `hailshot` **source** contents
  (other than porting the `setup.py` build helper), or the conda spec. Extend
  nothing at hidden-run time.
- Do not touch anything outside `/app` and the listed system paths
  (`site-packages`, `/opt/hailshot/gl/lib`, the conda envs, the pip installs).
- `/app/repair.sh` must be idempotent and must fully re-create
  `/app/env.txt` and `/app/rebuilt/` when run.
