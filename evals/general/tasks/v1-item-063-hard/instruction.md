# Item-063 (hard) — fit a sum of Lorentzian peaks to a Raman spectrum

`/app/raman.csv` holds a synthetic Raman spectrum with two columns:

```
wavenumber_cm1,intensity
```

There are **three** overlapping Lorentzian (Cauchy) peaks plus a small deterministic
background-component that behaves like low-amplitude sinusoidal noise. A Lorentzian
peak centered at `c` with peak height `H` and half-width `g` is:

```
L(w; H, c, g) = H * g^2 / ((w - c)^2 + g^2)
```

Write a Python program at `/app/fit.py` that fits the model

```
y(w) = L(w; A0,c0,g0) + L(w; A1,c1,g1) + L(w; A2,c2,g2) + baseline(w)
```

where the baseline is assumed zero for fitting (i.e. fit the pure 3-Lorentzian sum).
Use `scipy.optimize.curve_fit` with the fixed initial guess

```
p0 = [80, 540, 18, 60, 585, 12, 60, 720, 10]
```

which corresponds to `[A0, c0, g0, A1, c1, g1, A2, c2, g2]`, and box bounds

```
lower = [0,  500, 1,  0,  520, 1,  0,  650, 1]
upper = [300, 600, 60, 300, 600, 60, 300, 800, 60]
```

Set `maxfev=50000`.

## Deliverable

Write `/app/fit.json`:

```json
{
  "peaks": [
    {"center": 539.97, "height": 96.11, "width": 22.01},
    {"center": 584.96, "height": 69.59, "width": 10.93},
    {"center": 719.84, "height": 83.97, "width": 35.30}
  ],
  "residual_rms": 0.375
}
```

- `peaks` must have **exactly three** objects, sorted by ascending `center`.
- `center`, `height`, `width` are the fitted `c`, `A`, `g` parameters for each peak
  (rounded to as many digits as you like).
- `residual_rms` is `sqrt(mean((y - fit)^2))` over all 300 points.

## Verification

The verifier runs the **same** `curve_fit` from the same CSV, same `p0`, same
bounds. It then checks:
- each of your three peak centers is within `0.5` cm^-1 of the reference center,
- each height within 2%, each width within 2%,
- your `residual_rms` is within 10% of the reference RMS.

Do not modify `raman.csv`. Run the program so `/app/fit.json` is written.