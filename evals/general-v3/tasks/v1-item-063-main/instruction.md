# Fit a Raman spectrum as a sum of Lorentzian peaks

## Context

`/app/data/spec.csv` contains a **Raman-style spectrum**: columns `x,y`
(wavenumber in `cm^-1`, intensity), comma-separated, with a `x,y` header row.
The signal is a **baseline offset plus three smooth Lorentzian peaks**. /reference.
Your job: fit the Lorentzian sum model with SciPy/NumPy, inspect the residuals,
and write a machine-readable result.

## Model

Lorentzian (Cauchy-like) curves on a real baseline constant `b`:

```
y(x) = b + sum_i A_i * w_i^2 / ( (x - c_i)^2 + w_i^2 )
```

3 peaks → 1 baseline + 9 peak parameters (amplitude `A_i`, center `c_i`,
half-width `w_i`). Amplitudes are physical positive (peaks, not dips).

## Steps

1. Read `/app/data/spec.csv` into arrays `x`, `y` (skip the header row).
2. Implement the model above and fit with `scipy.optimize.curve_fit` or
   `least_squares`. Use a reasonable automatic initial guess (e.g., pick
   centers from local maxima, small widths, amplitudes from peak-minus-floor),
   and an iterative refinement (curve_fit returns the fitted coefs).
3. **Inspect residuals**: compute residual RMS over the grid. For this clean
   synthetic spectrum the exact fit is essentially perfect (RMS ~1e-10).
   Verify fitted centers lie within `[300,1600]` and widths are positive.
4. **Write** `/app/out/fit.json`:

   ```json
   {
     "baseline": <float b>,
     "peaks": [
        {"amplitude": A1, "center": c1, "width": w1},
        {"amplitude": A2, "center": c2, "width": w2},
        {"amplitude": A3, "center": c3, "width": w3}
     ],
     "rms": <float residual RMS>
   }
   ```

   `peaks` has 3 elements; `rms` is a float.

## Success criteria

- `/app/out/fit.json` exists and parses.
- Reconstructing `y_model` from the reported `baseline`/`peaks` over the CSV
  `x` grid gives residual RMS **≪ 0.5** (the true fit is exact to ~1e-9).
- The reported `rms` matches the verifier's own residual computation to
  tolerance.