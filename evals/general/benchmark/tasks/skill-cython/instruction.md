Under `/app/math` is a small Cython source file `fastmath.pyx`:

```cython
# cython: language_level=3
def square(long x):
    return x * x

def sum_squares(long n):
    cdef long i
    cdef long s = 0
    for i in range(1, n + 1):
        s += square(i)
    return s
```

Your job: **compile it into an importable Cython/C extension** named `fastmath`, import it from Python, call `sum_squares(100)`, and write the returned integer (as a plain string of digits) to `/app/result.txt`.

Recommended steps (work inside `/app/math`):

1. Create a `setup.py` that builds the extension using `Cython.Build.cythonize` plus `setuptools.Extension`:
   ```python
   from setuptools import setup, Extension
   from Cython.Build import cythonize
   ext = Extension("fastmath", ["fastmath.pyx"])
   setup(name="fastmath", ext_modules=cythonize([ext], language_level=3), packages=[])
   ```
2. Build inline with: `python setup.py build_ext --inplace`
   This drops a `fastmath.*.so` file into `/app/math`.
3. Compute the result. The mathematical value of `sum_squares(100)` is the sum of the first 100 square integers. Verify your compiled extension returns that exact value (it is a well-known closed-form value: `n(n+1)(2n+1)/6` for n=100).
4. Write the digit string of that result to `/app/result.txt`.

The verifier checks that `/app/result.txt` contains the correct value and that a compiled `fastmath` extension artifact exists.