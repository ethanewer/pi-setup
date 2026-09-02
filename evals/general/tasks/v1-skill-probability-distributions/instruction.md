# Normal distribution probability

X is a normally distributed random variable with:

- mean `mu = 50`
- standard deviation `sigma = 12`

Write a Python program `/app/ndist.py` that computes the probability `P(X <= 44)` for this normal distribution and writes the numeric result to `/app/result.json` as:

```json
{"p": <the probability value, as a float>}
```

Use the standard normal CDF identity:

```
P(X <= x) = 0.5 * (1 + erf((x - mu) / (sigma * sqrt(2))))
```

where `erf` is the error function available from Python's `math` module (`math.erf`). Store the value to enough decimal places (10 or more). Then run `/app/ndist.py` so that `/app/result.json` exists.

The verifier recomputes the same value from the formula using the mean and sigma above and checks it matches within `1e-6` absolute difference.

## What to verify
`/app/result.json` must exist and its `"p"` field must equal `0.5 * (1 + erf((44 - 50) / (12 * sqrt(2))))` up to `1e-6`.