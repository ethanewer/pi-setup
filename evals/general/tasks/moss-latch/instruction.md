# Rebuild the Larch DSP extension for numpy 2.x

`/app/src/grainflow/` contains the vendored source of **grainflow**, the Cython
window/ramp kernel package of the Larch DSP kit. The container's toolchain has
been moved to a **numpy 2.x** release (numpy >= 2.0, Cython < 3.1, setuptools,
compilers all already installed; the box is offline). The vendored package has
never been rebuilt on this toolchain: its build configuration and parts of its
source still use legacy numpy interfaces that numpy 2.x removed, so the build
fails — and pieces that would build would crash at run time.

Your job: **repair the package so it builds and runs against the installed
numpy 2.x**, install it, and leave behind the artifacts below.

## Deliverables (both required)

1. `/app/build.sh` — a bash build script that, when run from any working
   directory in a fresh shell, rebuilds the (repaired) package under
   `/app/src/grainflow/` against the **installed** numpy and installs
   `grainflow` as a **regular package into the default interpreter's
   site-packages** (a normal install, not an editable/development install and
   not a `sys.path` hack). It must:
   - work fully offline (no network; everything needed is already installed);
   - be **idempotent**: running it twice in a row must succeed both times and
     leave a working installed package;
   - exit `0` on success.
2. `/app/probe_out.json` — the JSON report produced by actually running
   ```
   python3 /app/probe.py /app/probe_out.json
   ```
   after building and installing. `/app/probe.py` imports the installed
   `grainflow` module and probes it on the visible probe points. **Do not
   modify `/app/probe.py`** — the grader re-runs it verbatim and compares
   against its own expectations.

## Module contract (what the grader checks)

`grainflow` must expose, for **any** valid input (the grader probes hidden
cases you have not seen):

- `hann(n)` — `n` an integer `>= 1`. Returns a 1-D `numpy.ndarray` of dtype
  `float64` and length `n`. For `n == 1` the result is `[1.0]`; for `n > 1`
  element `k` (0-based) is `0.5 * (1 - cos(2*pi*k/(n-1)))`. Raises
  `ValueError` for `n < 1`.
- `ramp(n)` — `n` an integer `>= 0`. Returns a 1-D `numpy.ndarray` of dtype
  `float64` and length `n` where element `i` is `0.25 * i * i` (so `ramp(0)`
  is an empty array). Raises `ValueError` for `n < 0`.

Both functions must return genuine `numpy.ndarray` objects with dtype
`float64`, and `import grainflow` must work from any working directory in the
default interpreter (`python3`) without rebuilding.

You may rewrite `/app/src/grainflow/` freely (setup/build configuration,
`grainflow.pyx`, additional files) as long as the module contract above holds
and the build works against the installed numpy 2.x.

## Rules

- Do **not** modify `/app/probe.py`.
- Do **not** downgrade or install a different numpy (the grader asserts the
  installed numpy is still a 2.x release); the repair is in the
  grainflow build configuration and source, not in the toolchain.
- No network access.
- The installed package must come from the repaired source (the grader
  re-runs `/app/build.sh` itself, then re-checks everything).
