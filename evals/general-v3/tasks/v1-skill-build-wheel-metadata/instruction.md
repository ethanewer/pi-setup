In `/app/melonpkg` there is the source tree of a small Python package:

- `pkg/__init__.py` (imports `add` from core)
- `pkg/core.py` (defines `add(a, b)`)

The `pyproject.toml` in that directory is currently just a stub. Your job is to give the
project proper **build/wheel metadata** and build a wheel, then inspect the wheel's
metadata.

1. Write `/app/melonpkg/pyproject.toml` declaring, with the setuptools backend:

   - `[build-system]`: `requires = ["setuptools>=61"]`, `build-backend = "setuptools.build_meta"`
   - `[project]`: `name = "melonpkg"`, `version = "1.4.0"`,
     `description = "Melon math helpers"`, `requires-python = ">=3.8"`
   - `[tool.setuptools]`: `packages = ["pkg"]`

2. Build a wheel into `/app/dist` without touching the network, from inside
   `/app/melonpkg`:

   ```bash
   cd /app/melonpkg
   pip wheel . --no-build-isolation --no-deps -w /app/dist
   ```

3. Inspect the *built* wheel's metadata (its `*.dist-info/METADATA` file, e.g.
   `unzip -p /app/dist/*.whl '*/METADATA'`) and copy the two relevant lines out of it to
   a file `/app/meta_report.txt`, i.e. the file must contain a line `Name: melonpkg` and
   a line `Version: 1.4.0`.

The verifier unzips your wheel, checks the METADATA (`Name: melonpkg`,
`Version: 1.4.0`, `Requires-Python: >=3.8`), imports `pkg.core.add` from the wheel
contents, and checks `/app/meta_report.txt`.