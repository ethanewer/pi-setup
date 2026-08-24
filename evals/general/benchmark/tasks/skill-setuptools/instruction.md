# setuptools package build

Build and install a small Python package using **setuptools** (not `distutils`).

## Steps

1. Create a package named `greetpkg` at `/app/greetpkg/` with an `__init__.py` that
   defines:

   ```python
   def greet(name="harbor"):
       return "hello " + name
   ```

2. Create `/app/setup.py` that:
   - imports `setup` from **setuptools**,
   - calls `setup(...)` with `name="greetpkg-extra"` and `version="1.0.0"` and
     includes the `greetpkg` package (use `packages=["greetpkg"]`).

3. Install the package into the running Python environment:

   ```bash
   cd /app && pip install --no-cache-dir --force-reinstall .
   ```

4. After the install succeeds, write `/app/output.txt` by running:

   ```python
   import greetpkg
   with open("/app/output.txt", "w") as f:
       f.write(greetpkg.greet() + "\n")
   ```

   The file must contain exactly `hello harbor` on a single line (with a trailing
   newline).

## Requirements

- `/app/setup.py` must reference `setuptools` (never `distutils`).
- The package must be importable as `import greetpkg` after the install.
- Do not install anything from the network; the package source is local.

## Deliverables

- `/app/setup.py`
- `/app/greetpkg/__init__.py`
- `/app/output.txt` (content: `hello harbor\n`)