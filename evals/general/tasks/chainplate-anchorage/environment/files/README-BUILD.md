# Notes on building and testing this tree

The repository at `/app/src` is a real upstream project (matplotlib) checked
out at a pinned, shallow (single) commit. Everything needed to build and test
it offline is baked into this image:

- A complete Python build toolchain (`build-essential`, `pkg-config`,
  `ninja-build`, meson, meson-python, pybind11, gcc) and the runtime
  dependencies of matplotlib, all pip-pinned (`numpy`, `contourpy`, `cycler`,
  `kiwisolver`, `fonttools`, `packaging`, `certifi`, `pillow`, `pyparsing`,
  `python-dateutil`, `pytest`).
- The library itself, compiled and installed in **editable** mode from
  `/app/src` (the C extensions — including the vendored freetype, harfbuzz
  and qhull — were built at image build time). Any edit you make to a `.py`
  file under `/app/src/lib` is live for the next `import matplotlib` without
  any rebuild or reinstall.
- `python3 -m pytest` from `/app/src` runs the project's own test suite.

Common commands (all offline):

    cd /app/src
    python3 -m pytest lib/matplotlib/tests/test_transforms.py::TestBasicTransform::test_contains_branch -q
    python3 - <<'EOF'
    import matplotlib; matplotlib.use('Agg')
    print(matplotlib.__file__)
    EOF

matplotlib's pytest configuration turns warnings into errors, and some test
modules contain slow or image-comparison tests, so run only targeted test
node ids.

Do not modify the `.git` directory (its history is intentionally shallow),
and do not commit, fetch or pull.