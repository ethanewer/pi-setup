# Numerical optimization

`/app/objective.py` defines a Python function `objective(x)` where `x` is a
2-element sequence (a vector). It is a smooth **convex** function of `x[0]` and `x[1]`,
and its global minimum occurs at some point strictly inside the box
`-4 <= x[0] <= 5` and `-4 <= x[1] <= 5`.

Write a Python script `/app/optimizer.py` that uses **SciPy** (`scipy.optimize.minimize`,
or another sound numerical optimizer) to find the minimizer of `objective` inside that
box, and writes `/app/solution.json`:

```json
{"x": [2.5, -1.25], "f": 0.0}
```

- `x` is the found minimizer `[x0, x1]` (floats),
- `f` is the objective value at that point (float).

Do not hardcode values without actually running an optimizer: your script must itself
import `objective` from `/app/objective.py` and run the optimization to produce the
result. Run your script so `/app/solution.json` exists. The verifier re-evaluates the
same `objective` at your reported `x` and checks that you are (numerically) at the
global minimum.