# Repair the Shale Forge data-analyst platform

`/app` contains the working tree of an internally-built analytics platform
("Shale Forge") plus several of its runtime components. The environment is
deliberately broken in seven independent ways. Your job: **diagnose and repair
all seven**, leave the environment fixed, and hand back two artifacts:
`/app/repair.sh` (a reusable, idempotent repair script) and `/app/verify.py`
(a verification script). An external grader will re-run the broken commands
after you and detect any that are still broken.

There is no network inside `/app`; every source you need is vendored under
`/app`. `apt`/`pip` may be used only against already-present local artifacts.
Work only under `/app` and the system paths listed below.

## Deliverables

Create exactly these two files:

1. **`/app/repair.sh`** — a `bash` script that applies every repair. It must be
   **idempotent** (safe to re-run; each step guarded so it skips work that is
   already done) and must exit `0` when run on an already-repaired container.
   Running it must leave all of the checks below passing.
2. **`/app/verify.py`** — a Python 3 script that re-runs every originally
   failing check (the ones listed under "What success looks like"), prints one
   `PASS`/`FAIL` line per check, prints `ALL_OK` and exits `0` when all pass.

You must **also apply the repairs to the live environment** (run them now), not
merely leave a script behind.

## The seven broken components

### 1. `kether` (default-interpreter package)
`/app/shelf/kether/` is the working, pure-Python build. The copy currently
installed in the default interpreter's site-packages is only a broken stub that
raises on `import kether`. Install the working build so that the **system
`python3`** (the default interpreter) can import it.

### 2. `spect` (edited build needing its targeted suite)
`/app/shelf/spect/` carries the **edited** version (`__version__ == '2.1.0'`).
A whitespace/noise fix was applied to the source but it has **not** been
reinstalled — the package currently in site-packages is the old build
(`__version__ == '0.3.0-unedited'`). Install the edited tree and run its own
test suite:

```
python3 -m pip install --no-build-isolation --no-deps --upgrade /app/shelf/spect
python3 -m pytest -q /app/shelf/spect/tests
```

The suite must be green (`N passed`). `spect.prefix_digest(s)` ignores all
whitespace; an all-whitespace/empty string returns the exact marker `EMPTY`;
otherwise it returns the sum of the codepoints of the non-whitespace characters
modulo `2**16`, printed as four lowercase hex digits (e.g. `'ab' -> '00c3'`).

### 3. `pyros` (Cython extension vs numpy 2.x)
`/app/shelf/pyros/` is a Cython extension. Its bundled `setup.py` still uses
the legacy `numpy.distutils` entry point, which was **removed in numpy 2.x**, so
building it that way fails. Port the build to a modern `setuptools` +
`Cython.Build.cythonize` configuration, compile it against the installed numpy,
and install the compiled artifact so that these work without re-building:

```
python3 -c "import pyros, numpy; print(numpy.__version__)"   # starts with 2.
python3 -c "import pyros; print(pyros.ring(3))"              # 55.0
python3 -c "import pyros; print(pyros.converge([2.0, 2.0]))" # 4.0
```

`pyros.ring(k)` = signed sum of squares of the first `|k|` positive integers
(`ring(5)=55.0`, `ring(-3)=-14.0`, `ring(0)=0.0`); `pyros.converge(xs)` sums a
numeric sequence. Both must work for any valid input (see hidden cases).

### 4. OSMesa loader
`/app/gloss/fern_gl.py` is the offscreen-GL loader used by the platform. It
searches only the directory list from the `$FERN_GL_LIB` env var (colon
separated, empty entries dropped) **then** the fixed location `/opt/osp/gl/lib`,
looking for `libOSMesa.so`, `libOSMesa.so.6`, or `libOSMesa.so.8`. It never
falls back to `ldconfig`. In the current image the directory `/opt/osp/gl/lib`
is empty, and `$FERN_GL_LIB` is unset. Make the loader succeed: place the
system OSMesa runtime library where the loader looks (the system library
`libOSMesa.so.8` already exists under `/usr/lib`). The loader must also behave
when `$FERN_GL_LIB` points at bogus/nonexistent directories: those entries are
skipped and loading must still succeed from `/opt/osp/gl/lib`. On success the
loader prints `OSMESA_OK` and exits `0`.

### 5. Interpreter shim
`/app/ima/runner/settings.json` is used by `/app/ima/runner/spire.py`. Before
it cProfile-executes each script it looks up the interpreter path in the
`python_shim` field. Write the python_shim field to the resolved absolute path
of the **system** python interpreter (`python3 -c "import sys;print(sys.executable)"`).
It must be a non-empty path to an existing, executable interpreter so that
`python3 /app/ima/runner/spire.py /app/ima/runner/target_probe.py` runs and
prints `SPIRE_OK`.

### 6. R statistical runtime
The platform's R self-test `/app/ima/runner/rself.py` also reads
`/app/ima/runner/settings.json` and uses the `rscript` field (an absolute,
executable path to `Rscript`) to run every R subprocess. Set `rscript` to the
path of `Rscript`, so `python3 /app/ima/runner/rself.py` exits `0` and prints
`R_SELFTEST`. R itself is pre-installed.

### 7. R Jupyter kernel + analysis package
The platform must expose an R Jupyter kernel. The R `IRkernel` package is
already installed on the image, but no user kernel has been registered.
Register a kernel whose (exactly this name):
```
Rscript --vanilla -e 'IRkernel::installspec(name="rcausal", displayname="R causal analyst", user=TRUE)'
```
After doing this, `jupyter kernelspec list` must list a kernel named `rcausal`
and `/root/.local/share/jupyter/kernels/rcausal/kernel.json` must exist with an
`argv[0]` that is an existing, executable R binary. The platform's causal
analysis package `jsonlite` is already installed; the R environment must be able
to `library(jsonlite)`.

## Hidden / edge cases the grader will probe
After the repair the grader independently re-runs the following edge data
(which you have not seen but must support generally):

- `kether.flows` on `[]`, on `[-0.5,1.5,3.0]`, on `[2,-2,3,-4]`,
- `spect.prefix_digest` on `"ab"`, `"a\tb"`, `"1 2 3 "`, `"Zz"`, `"   "`,
- `pyros.converge` on `[0.5,-1.5]`, `[2,2,2]`, `[]`, and `pyros.ring` on `1`,
  `-3`, `5`, `0`,
- `fern_gl.py` run with `FERN_GL_LIB` set to bogus directories (must still load
  and print `OSMESA_OK`).

Your implementations must be **general**, not hard-coded, for these inputs.

## Rules

- Do not modify `/app/gloss/fern_gl.py`, `/app/ima/runner/*.py`, the `target_probe.py`,
  or the `spect`/`kether`/`pyros` source contents other than to add/port the
  `pyros` build configuration.
- The env is fully offline. Do not touch anything outside `/app` and the listed
  system paths (site-packages, `/opt/osp/gl/lib`, `/root/.local/share/jupyter`).
- Leave both deliverables plus a working set of all the state the grader
  re-checks.