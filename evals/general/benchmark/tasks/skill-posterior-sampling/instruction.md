# Posterior sampling (Bayesian update)

You are modeling success probability $p$ of a Bernoulli process with a **Beta prior** and a **binomial likelihood** — the standard conjugate pair.

- Prior: $p \sim \mathrm{Beta}(\alpha=2,\ \beta=5)$
- Likelihood: you observe $n = 24$ independent trials with $s = 10$ successes.

Because Beta is conjugate to the binomial, the **posterior** is again Beta:

- posterior $\alpha' = \alpha + s$
- posterior $\beta' = \beta + (n - s)$

Write `/app/posterior.txt` with two lines:

- Line 1: two integers separated by a space: `α' β'` (posterior alpha and beta).
- Line 2: the **posterior mean** $\alpha'/(\alpha'+\beta')$, rounded to 4 decimal places.

The verifier recomputes the exact integer parameters and the mean (rounded to 4 decimals) and checks both lines. Python's standard library is sufficient.