`/app/regression.csv` holds a small high-dimensional numeric dataset: 20 rows, 5 feature columns `x0,x1,x2,x3,x4` followed by a target column `y`. (There is a header row naming these columns.)

The data were generated from an **exact linear model**: `y = beta0*x0 + beta1*x1 + beta2*x2 + beta3*x3 + beta4*x4` with integer coefficients, so a least-squares fit recovers them to within floating-point error.

Use `numpy` to fit the linear coefficients with ordinary least squares, for example:

```python
import numpy as np
data = np.genfromtxt('/app/regression.csv', delimiter=',', skip_header=1)
X = data[:, :5]
y = data[:, 5]
coefs, *_ = np.linalg.lstsq(X, y, rcond=None)
```

Write the five fitted coefficients to `/app/coeffs.txt` as a single line of **space-separated decimal numbers** (each coefficient with enough precision to distinguish it, e.g. 6+ decimals; do not round to 0 where a small nonzero coefficient exists).

The verifier independently runs the same least-squares fit on the same CSV and compares each coefficient numerically (tolerance 1e-3).