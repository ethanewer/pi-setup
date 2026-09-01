# Automatic differentiation with autograd

The Python package **`autograd`** is installed in this environment. It provides reverse-mode automatic differentiation on NumPy-based code: `autograd.grad(f, argnum=k)` returns a function that computes the derivative of `f` with respect to its `k`-th positional argument (use `autograd.numpy` as the NumPy module so gradients propagate).

Consider the scalar function

```
f(x, y) = x**2 * y + cos(x)
```

Write `/app/solve.py` that:

1. Imports `autograd` and `autograd.numpy as np`.
2. Defines `f(x, y) = x**2 * y + np.cos(x)`.
3. Uses `autograd.grad` to compute the partial derivatives of `f` at the point `(x=2.0, y=3.0)`:
   - `df_dx` — partial derivative with respect to `x` (`grad(f, 0)` evaluated at `(2.0, 3.0)`).
   - `df_dy` — partial derivative with respect to `y` (`grad(f, 1)` evaluated at `(2.0, 3.0)`).
4. Writes `/app/answer.json`:

```json
{"df_dx": 11.0907, "df_dy": 4.0}
```

where `df_dx` and `df_dy` are the numeric values autograd computes (round to at least 4 decimals). Run `python3 /app/solve.py` so the file is produced. Do not hard-code the numbers — compute them with autograd.

Reference (analytic, for your own checks): `∂f/∂x = 2xy − sin(x)`, `∂f/∂y = x²`.