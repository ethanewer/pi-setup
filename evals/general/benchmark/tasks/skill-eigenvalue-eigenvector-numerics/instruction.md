# Eigenvalue / eigenvector numerics with numpy

`/app/matrix.txt` contains a 2x2 matrix, two rows, whitespace-separated
numbers:

```
3 1
0 5
```

## Task

Write a Python 3 script `/app/eigens.py` that uses **numpy** to compute the
eigenvalues and a dominant eigenvector of this matrix, then writes
`/app/eigen.txt` with exactly three lines:

```
eigenvalues 3.0 5.0
dominant 5.0
eigenvector 0.447213595499958 0.894427190999916
```

where

1. `eigenvalues` — the two eigenvalues sorted in **ascending** order,
   separated by a space, formatted to at least 6 decimal places.
2. `dominant` — the largest (dominant) eigenvalue.
3. `eigenvector` — a **unit** eigenvector (Euclidean norm 1) belonging to the
   dominant eigenvalue, two components separated by a space. Any correct unit
   eigenvector is acceptable (sign and ordering conventions don't matter).

Suggested approach (`numpy.linalg.eig` gives both):

```python
import numpy as np
M = np.loadtxt('/app/matrix.txt')
vals, vecs = np.linalg.eig(M)
```

## Verification you should run yourself

Your own script should satisfy:

- `np.allclose(sorted(vals), [3.0, 5.0], atol=1e-9)` — the true eigenvalues
  are `3.0` and `5.0` (the matrix is triangular).
- With `v` your eigenvector and `lam` the dominant eigenvalue:
  `np.linalg.norm(v) == 1` (within floating point) and
  `np.allclose(M @ v, lam * v, atol=1e-9)`.

The verifier recomputes the eigenvalues with numpy, and checks that your
eigenvalues, dominant value, and the eigenpair property `M v = lam v` with a
unit vector all hold to tolerance `1e-3`.