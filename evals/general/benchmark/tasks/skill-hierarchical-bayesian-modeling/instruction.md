Consider a **hierarchical (nested) Bayesian model** with a single shared (population) mean parameter `mu`, in the Normal-Normal-Normal conjugate family:

- Prior: `mu ~ Normal(mu0 = 0, sigma0^2 = 1)` — i.e. prior precision `pi0 = 1`, prior mean `mu0 = 0`.
- Each group's observed mean is a noisy estimate of `mu`: group A reports `mA = 4` with effective precision `piA = 1`; group B reports `mB = 26` with effective precision `piB = 2` (e.g. it has more observations or smaller within-group variance).

For this conjugate setup the posterior for `mu` (the shared parameter) has:

- posterior precision: `pi_post = pi0 + piA + piB`
- posterior mean: `mu_post = (pi0*mu0 + piA*mA + piB*mB) / pi_post`

The posterior mean is the Bayesian estimate of the shared population mean under the hierarchy.

Compute `mu_post` with the numbers above and write it to `/app/answer.txt` as a plain decimal number (floating point is fine).

The verifier recomputes the same posterior mean from the constants above and compares numerically (tolerance 0.01).