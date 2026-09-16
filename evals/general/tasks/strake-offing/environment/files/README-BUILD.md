# strake-offing: image build notes

This image was built from `tasks/strake-offing/environment/Dockerfile`:

- base `bench-base:python-3.12` (Python 3.12, pip 25.0.1, no setuptools);
- apt: `build-essential pkg-config ninja-build` (matplotlib's compile deps);
- pip (all exact pins): meson-python 0.21.1, pybind11 3.1.0,
  setuptools-scm 10.2.3, ninja 1.13.2, meson 1.12.0, setuptools 84.0.0,
  wheel 0.48.0, numpy 2.5.3, contourpy 1.4.0, cycler 0.12.1, kiwisolver
  1.5.1, fonttools 4.65.0, packaging 26.3, certifi 2026.7.22, pillow 12.3.0,
  pytest 9.1.1, pyparsing 3.1.4 (pinned <3.2.0 because matplotlib's pytest
  config turns the pyparsing 3.2.0 deprecation warning into an error);
- `/app/src`: shallow single-commit clone of matplotlib/matplotlib detached at
  the pinned upstream revision `496ae85214a7029d5c8eca320cb45f013b535dfe`,
  installed editable with `pip install --no-build-isolation -e .`
  (meson-python editable wheel; compiled extensions land in
  `/app/src/build/cp312`);
- `/opt/prefix`: a pristine, importable copy of the package exactly as built
  at that same pinned revision (upstream `lib/` archive + meson install-dir
  generated files + compiled extensions at module-correct locations);
  importable only through the editable-hook skip variable
  `MESONPY_EDITABLE_SKIP=/app/src/build/cp312` with
  `PYTHONPATH=/opt/prefix/lib`;
- `/opt/golden`: the upstream regression test for the histogram-input bug and
  the full test file it was extracted from, taken verbatim from the upstream
  test suite at image build time via a throwaway clone that is deleted during
  the build — no upstream revision other than the pinned one is reachable in
  the shipped repository;
- `/opt/pins`: sha256 trust anchors for the golden files, the pristine
  package, and a full snapshot of site-packages (closes monkeypatch attacks).

Measured on this host: fresh build ~55 s at 1 CPU; image ~1.25 GB total.