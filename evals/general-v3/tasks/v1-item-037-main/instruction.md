# Dominant eigenpair of a non-symmetric matrix (with complex eigenvalues)

## Context

`/app/data/matrix.txt` holds a **5×5 non-symmetric** real matrix (space-separated
rows). Your task: compute, using NumPy's linear-algebra routines (power iteration
or `numpy.linalg.eig`), the **dominant eigenpair** of this matrix:

- $\lambda$ = the eigenvalue of **largest magnitude** ($|\lambda|$),
- $\mathbf v$ = a corresponding **unit** ($\|\mathbf v\|_2 = 1$) eigenvector.

The matrix is deliberately **non-symmetric** and **not** guaranteed to have
purely real eigenvalues: some eigenpairs are **complex**. Your code must handle
complex eigenvalues/eigenvectors correctly (never ignore the imaginary part of
$|\lambda|$ when picking the maximum).

## What to do

1. Read the matrix `/app/data/matrix.txt` (5 rows, 5 columns of real numbers).
2. Compute all eigenvalues and eigenvectors
   (e.g. `numpy.linalg.eig(A)`).
3. Select the eigenvalue with the **largest magnitude**
   (`index = argmax(|eigenvalues|)`). This is $\lambda$; the corresponding
   column of the eigenvector matrix is $\mathbf v$.
4. **Normalize** $\mathbf v$ to unit 2-norm (still complex after column; don't
   silently drop the imaginary part). Optionally take the real part only if the
   imaginary part is negligible (below ~1e-9).
5. **Check normalization and residuals** (self-check): confirm
   $\|\mathbf v\|_2 \approx 1$ and that $A\mathbf v \approx \lambda \mathbf v$.
6. Write `/app/out/eigen.json`:

   ```json
   {
     "lambda": <dominant eigenvalue, as a JSON real number — the real part if
                complex with negligible imaginary part>,
     "eigenvector": [ <unit eigenvector entries, in order, ≥ 5 numbers> ],
     "residual": <||A v - lambda v||_2>
   }
   ```

   `lambda` and `eigenvector` should be written as real numbers (the real
   parts). `residual` must be a float.

## Success criteria

- `/app/out/eigen.json` exists and parses.
- $\lambda$ is the **largest-magnitude** eigenvalue of the matrix (verified
  against a fresh `eig` recomputation).
- $A \mathbf v \approx \lambda \mathbf v$ (residual small relative to the
  largest eigenvalue magnitude), and $\|\mathbf v\| \approx 1$.
- The reported vector lies in the dominant eigenspace (no spurious arbitrary
  vector accepted).

Note: you must get the **sign / normalization** of the eigenvector correct so
that these checks pass; a negated normalized eigenvector is also valid.