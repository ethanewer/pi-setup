In `/app` there is a C source file `numc.c`: a minimal CPython **C extension module**
that implements two functions via the Python C API (`PyArg_ParseTuple`, `PyLong_FromLong`,
`PyFloat_FromDouble`):

- `numc.add(a, b)` — adds two Python ints and returns the sum as an int
- `numc.mul(a, b)` — multiplies two Python floats and returns the product as a float

Your job: build this C extension and use it.

1. Write a `setup.py` in `/app` that uses `setuptools` and declares an `Extension`
   named `numc` with `sources=["numc.c"]` (plain C, default language).
2. Build the extension in place:

   ```bash
   cd /app
   python setup.py build_ext --inplace
   ```

   This produces a `numc.cpython-3xx-*.so` file in `/app`.
3. Verify it works, then write `/app/out.json` containing exactly:

   ```json
   {"add": 42, "mul": 42.0}
   ```

   which is what `numc.add(30, 12)` and `numc.mul(6.0, 7.0)` return.

The verifier imports `numc` from `/app` and checks both function results and the
contents of `/app/out.json`.