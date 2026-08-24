# Statistical testing

SciPy is installed (`import scipy`). Two datasets are defined inline in your script (no input files).

Write a Python script `/app/stats.py` that performs two hypothesis tests and reports their statistics:

## 1. Two-sample Student's t-test (independent)

```python
import numpy as np
from scipy import stats

A = np.array([12.1, 13.0, 11.8, 12.7, 12.4])
B = np.array([14.2, 13.9, 15.1, 14.0, 13.7])
```

Compute `t, p = stats.ttest_ind(A, B)` (unpaired, equal population variances).

## 2. Chi-square test of independence on a contingency table

```python
table = np.array([[5, 12, 8],
                  [6, 9, 10]])
```

Compute `chi2, p, dof, expected = stats.chi2_contingency(table)`.

## 3. Output

Write `/app/stats.txt` with exactly four lines, each value rounded to **6 decimal places**:

```
ttest_stat=<t rounded to 6 decimals>
ttest_p=<p rounded to 6 decimals>
chi2_stat=<chi2 rounded to 6 decimals>
chi2_p=<p rounded to 6 decimals>
```

For example: `ttest_stat=-4.291347`.

Then run `/app/stats.py` so `/app/stats.txt` exists.

The verifier recomputes both tests itself (same data, same SciPy functions) and requires each reported value to match its own recomputation to within `1e-5`.