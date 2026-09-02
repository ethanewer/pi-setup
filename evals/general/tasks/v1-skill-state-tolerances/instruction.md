# State tolerances

Consider a physical process whose **reference (expected) state** and **measured (actual) state** are each described by a set of numeric channels. Each channel has an allowed **tolerance**: an absolute deviation from its reference value that is still considered in-spec.

Three JSON files are provided in `/app`:

- `/app/reference.json` — the expected state:
  ```json
  {"temp": 21.0, "pressure": 1013.25, "level": 2.0}
  ```
- `/app/actual.json` — the measured state:
  ```json
  {"temp": 21.8, "pressure": 1013.3, "level": 2.6}
  ```
- `/app/tolerance.json` — the allowed per-channel tolerance:
  ```json
  {"temp": 0.5, "pressure": 0.5, "level": 0.2}
  ```

A channel is **in spec** when `abs(actual - reference) <= tolerance`.

Write a Python script `/app/check.py` that:

1. Loads the three JSON files.
2. For each channel in the reference, computes whether it is within tolerance (compare using absolute difference `<=`).
3. Writes `/app/result.txt` with:
   - one line per channel: `<channel>=PASS` or `<channel>=FAIL`, in the key order `temp`, `pressure`, `level`;
   - a final line `all=PASS` if every channel passed, otherwise `all=FAIL`.

Given the provided values, the expected output is:

```
temp=FAIL
pressure=PASS
level=FAIL
all=FAIL
```

Then run `/app/check.py` so `/app/result.txt` exists. The verifier recomputes the per-channel tolerance check from the same three JSON files and requires the exact lines above (tolerating trailing whitespace / CRLF).