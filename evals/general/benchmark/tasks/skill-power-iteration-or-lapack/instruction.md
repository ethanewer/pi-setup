# Dominant eigenvalue (power iteration / LAPACK)

`/app/matrix.txt` holds a 2×2 real matrix, one row per line (numbers separated by whitespace):

```
4 1
1 3
```

Compute the matrix's **dominant eigenvalue** (the eigenvalue with the largest absolute value).

Two well-known approaches are acceptable:

- **Power iteration fallback** (no libraries): start from `v = [1, 1]`, repeatedly apply `v = A·v`, normalize v to unit Euclidean norm (a few thousand iterations), then estimate the dominant eigenvalue through a Rayleigh-style quotient `λ ≈ (A·v)·v / (v·v)`.
- **LAPACK / linear-algebra library** (e.g. `numpy.linalg.eigvals` if you install numpy) directly.

Write the result to `/app/eigenvalue.txt`: a single decimal, the dominant eigenvalue, rounded to 4 decimal places. For this particular matrix the dominant eigenvalue is a positive number slightly larger than 4 (≈ 4.618034).

The verifier recomputes the dominant eigenvalue itself (with the same power-iteration method) and checks your value is within a small tolerance.