# Exponential decay curve fit with SciPy

`/app/decay.csv` is a CSV file with a header row `t,y` followed by 20 data rows. The
data follow a decaying exponential law `y ≈ a * exp(-b * t)` plus small Gaussian noise.

Write a Python script `/app/fit.py` that uses **SciPy / NumPy** to fit this model:

```python
def model(t, a, b):
    return a * np.exp(-b * t)
```

using `scipy.optimize.curve_fit` (non-linear least squares) on the data in
`/app/decay.csv` (load it with `numpy.loadtxt(..., delimiter=',', skiprows=1)` or
`csv`). Then write `/app/fit.json`:

```json
{"a": 2.9987, "b": 0.8012}
```

- both values are the fitted parameters rounded to **4 decimal places**,
- `b` must be positive (decreasing curve).

Run your script so `/app/fit.json` exists. The verifier fits the same model to the
same data and checks your reported parameters within a small tolerance.