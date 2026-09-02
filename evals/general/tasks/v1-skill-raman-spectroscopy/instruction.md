# Raman spectroscopy

`/app/data.json`:

```json
{
  "laser_wavenumber_cm1": 18796.99,
  "lines": [
    {"label": "A", "wavelength_nm": 585.0},
    {"label": "B", "wavelength_nm": 553.0}
  ]
}
```

Write `/app/shift.py` that reads the laser wavenumber `nu0` and each line's scattered wavelength, computes the Raman shift for each line as

```
shift = nu0 - 1e7 / wavelength_nm
```

rounds each shift to **1 decimal place**, and writes `/app/result.json`:

```json
{"shifts": [{"label": "A", "shift_cm1": 1703.0}, {"label": "B", "shift_cm1": 713.8}]}
```

Run `python3 /app/shift.py` so the file is produced. The verifier recomputes the shifts from the same input; do not hardcode the numbers.
