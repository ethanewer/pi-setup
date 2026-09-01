# GEMM matrix multiply with NumPy/BLAS

BLAS (Basic Linear Algebra Subprograms) is the standard low-level interface for dense linear algebra (matrix multiplication, etc.). In Python you can drive BLAS through **NumPy**'s vectorized operations (`numpy.matmul` / `@` or `numpy.dot`), which dispatch to an optimized BLAS implementation internally.

Two fixed integer matrices are defined as:

```
A = [[1, 2],
     [3, 4]]

B = [[5, 6],
     [7, 8]]
```

Write a Python program `/app/gemm.py` that:

1. Builds the matrices `A` and `B` above as NumPy `ndarray`s.
2. Computes the matrix product `C = A @ B`.
3. Converts the result to a plain Python list of lists of ints (the entries are integers).
4. Writes `/app/product.json` as:

```json
{"C": [[<r0c0>, <r0c1>], [<r1c0>, <r1c1>]]}
```

Write the **actual computed entries** of `A @ B` (the placeholders above are just showing the structure). Run `/app/gemm.py` so the file exists. The verifier recomputes `A @ B` with NumPy and requires your entries to match exactly.