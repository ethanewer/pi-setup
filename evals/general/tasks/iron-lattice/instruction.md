# Estimate a dominant mode of a symmetric matrix

Write a self-contained Python program at `/app/power.py` that estimates the
largest-magnitude eigenvalue (dominant mode) and the corresponding normalized
eigenvector of a real symmetric matrix using the **power iteration** method.

## Command-line contract

```
python3 /app/power.py <matrix_file> <output_json_path>
```

- `<matrix_file>` contains a square matrix of whitespace-separated real numbers.
  Every row has the same number of entries as the number of rows. Blank lines are
  ignored.
- `<output_json_path>` is the file to write. The program must create it (and any
  parent directories) if it does not exist, and overwrite it if it does.

The program must work for **any** input that satisfies the documented contract
— not just the provided example file.

## Algorithm requirements

1. Start from the all-ones vector `[1, 1, ..., 1]`, then normalize it to unit
   Euclidean (L2) norm.
2. Repeatedly apply the matrix: `w = A @ v`, normalize `w` to unit Euclidean
   norm, and take that as the new `v`.
3. Stop when the Euclidean norm of the change in the normalized vector is less
   than `1e-10`. Bound the number of iterations (e.g. 200000) so it always
   terminates.
4. Estimate the eigenvalue as the Rayleigh quotient `v^T A v` (equivalently
   `v^T w` where `w = A @ v`) using the final normalized vector.
5. Write the eigenvalue and the final normalized eigenvector to the output file.

## Output format

The output must be a single JSON object:

```json
{
  "eigenvalue": 4.732050807568877,
  "vector": [0.7886751346, 0.5773502692, 0.2113248654]
}
```

- `eigenvalue` is a float (scientific notation is acceptable).
- `vector` is a list of floats, one per row/column, in the same order as the
  matrix. The vector must be a unit vector under the Euclidean norm.
- Bring the program to a stable approximation: with a fresh arbitrary input the
  reported eigenvalue must be accurate to roughly 1e-6 (absolute) and the
  reported vector proportional to a true dominant eigenvector to roughly 1e-6
  of dot product.

## Edge cases to handle

- **1×1 matrix**: the only eigenvalue is the single entry; the eigenvector is
  `[1.0]` (the unit vector). Your iteration must handle a zero-length change.
- **Diagonal matrix**: the dominant eigenvector is the corresponding standard
  basis vector (`[1, 0, 0, ...]`), must be recovered.
- **Larger matrices** (e.g. 4×4) with several nonzero entries.
- Use `float` for all arithmetic; do not restrict to integer-input matrices —
  fractional entries must work.

## Guarantee and constraints

- The matrix is real and symmetric, and has a **unique** largest-magnitude
  (dominant) eigenvalue, so power iteration converges from the all-ones start.
- You may NOT modify the input matrix files in any way.
- Do not require any third-party packages beyond the Python 3 standard library.

## Deliverable

Write `/app/power.py` (make it executable with `chmod +x`). The verifier will run
it on the provided matrix **and on additional unseen matrices** under the exact
command-line contract above, including 1×1, diagonal, 2×2, and 4×4 matrices, and
compare the JSON output. All the covered edge cases above are exercised by hidden
cases.