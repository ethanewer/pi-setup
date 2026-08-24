# A C extension that uses the NumPy C API

Write a Python C extension module named **`sqmod`** that exposes one function:

```python
sqmod.squares(arr) -> numpy.ndarray
```

`arr` is a 1-dimensional NumPy array of dtype `int64` with `n` elements.
`squares` must return a **new** 1-dimensional NumPy array of dtype `int64` with `n`
elements where `out[i] == arr[i] * arr[i]`.

The implementation must be **in C**, using the **NumPy C API** (`numpy/arrayobject.h`,
`PyArray_SimpleNew`, `PyArray_DATA`, `import_array()`), not Python-level loops.

## Layout

- Write the C source to `/app/src/sqmod.c` and the build script to `/app/src/setup.py`.
- Your `setup.py` must include the NumPy headers via
  `include_dirs=[numpy.get_include()]` and the include path for the Python headers
  (setuptools adds it automatically).
- Build it in place from `/app/src` (use GCC; a compiler is installed):
  `cd /app/src && python3 setup.py build_ext --inplace`
  This produces `/app/src/sqmod*.so`.
- Write `/app/run.py` that inserts `/app/src` at the front of `sys.path`, imports
  `sqmod`, builds input array `x = numpy.array([1,2,3,4,5,6,7,8], dtype=numpy.int64)`,
  computes `y = sqmod.squares(x)`, and writes `/app/result.json`:

  ```json
  {"in": [1, 2, 3, 4, 5, 6, 7, 8], "out": [1, 4, 9, 16, 25, 36, 49, 64]}
  ```

- Run `/app/run.py` so `/app/result.json` exists with the correct values.

The verifier recomputes the per-element squares with NumPy and compares. NumPy,
setuptools and wheel are already installed; `gcc`/`make` are available.