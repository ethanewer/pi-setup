# Lorentzian curves

A **Lorentzian** (Cauchy, Breit–Wigner) peak profile has the functional form

```
f(x) = A * (gamma / pi) / ((x - x0)^2 + gamma^2)
```

with peak height `f(x0) = A / (pi * gamma)` (unnormalized amplitude `A`), and **full width at half maximum (FWHM) = 2 * gamma**. The value at `x0 ± gamma` equals exactly half the peak height.

Consider a Lorentzian with:

- `x0 = 5.0` (peak position)
- `gamma = 0.8`
- `A = 2.0`

Compute:

1. **FWHM** = `2 * gamma` = `2 * 0.8` = **1.6**.
2. **Peak height** `f(x0)` = `A / (pi * gamma)` = `2.0 / (pi * 0.8)` ≈ **0.79577**.

Write both values to `/app/answer.json`:

```json
{
  "fwhm": 1.6,
  "peak_height": 0.79577
}
```

`fwhm` must be exact (tolerance 1e-6); `peak_height` is accepted within tolerance 0.001.