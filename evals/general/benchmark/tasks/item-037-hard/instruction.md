# Item-037 (hard) — full eigendecomposition of a non-symmetric complex matrix

`/app/matrix.json` holds a single 6x6 **complex, non-Hermitian** matrix. The array is
stored as a JSON list-of-lists; each entry is `{"re": ... , "im": ...}` giving the
real and imaginary parts of one complex element. Row 0 comes first, then row 1, etc.

Write a Python program at `/app/eig.py` that computes the **complete**
eigendecomposition of this matrix using NumPy (e.g. `numpy.linalg.eig`), and writes
`/app/eig.json`.

## Contract

The matrix is non-symmetric and has six **distinct** complex eigenvalues (a
conjugate pair and a real negative and several off-diagonal complex entries are
present). Some eigenvalues are close in magnitude, so use a numerically robust
routine (LAPACK-backed `numpy.linalg.eig`).

Produce `/app/eig.json`:

```json
{
  "eigenvalues": [ {"re": ... , "im": ...}, ... ],
  "eigenvectors": [ [{"re":..., "im":...}, ... six elements ...], ... ]
}
```

- `eigenvalues` is a length-6 array; `eigenvectors` is a 6x6 array whose **columns**
  are the eigenvectors, in the **same index order** as `eigenvalues[i]`.
- Every eigenvector column must be normalized to Euclidean unit norm
  (`v / np.linalg.norm(v)`), so `||v_i|| == 1` up to round-off.
- Numbers may be written with as much precision as you like (the verifier uses
  floating-point tolerance).

## Verification (how your work is judged)

The verifier re-reads `matrix.json`, recomputes its own eigendecomposition, and
checks every one of your (eigenvalue, eigenvector) pairs:

1. your eigenvector is unit-norm,
2. `|| A @ v_i - lambda_i * v_i || < 1e-6` for each pair (the "residual"),
3. the multiset of your eigenvalues equals the reference eigenvalues (sorted
   real-part-first, then descending imaginary magnitude) within `1e-7`.

Do not modify `matrix.json`. Run the program so `/app/eig.json` exists. The result
must be deterministic for this fixed input.