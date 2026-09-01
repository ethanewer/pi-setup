# MCMC diagnostics — Gelman–Rubin R-hat

Two MCMC chains were run targeting the same posterior. Compute the **Gelman–Rubin convergence statistic** (often written `R-hat` or `R̂`) for the scalar parameter:

```
chain1 = [6, 8, 10, 12]
chain2 = [8, 10, 12, 14]
```

Each chain has length `n = 4`; there are `m = 2` chains. Follow the standard estimation:

1. Per-chain means: `theta1 = 9`, `theta2 = 11`; grand mean `theta_bar = 10`.
2. Within-chain variance `W = (s1^2 + s2^2) / m`, where `s_j^2 = (1/(n-1)) * sum_i (x_ij - theta_j)^2`. Each chain has deviations `{-3,-1,1,3}` with squares `20`, so `s1^2 = s2^2 = 20/3` and `W = 20/3`.
3. Between-chain variance `B = (n/(m-1)) * sum_j (theta_j - theta_bar)^2 = 4 * (1+1) = 8`.
4. Pooled variance estimate `var_hat = ((n-1)/n) * W + B/n = (3/4)*(20/3) + 8/4 = 5 + 2 = 7`.
5. `R-hat = sqrt(var_hat / W) = sqrt(7 / (20/3)) = sqrt(21/20) ≈ 1.0247`.

Write `R-hat` to `/app/answer.json`:

```json
{"rhat": 1.0247}
```

Accepted within tolerance `0.01` of the formula value above.