# Juniper Latch — repair the sigdeck windowing stage

The `sigdeck` telemetry package at `/app/sigdeck` failed its acceptance run:
the analysis stage computes wrong RMS windows and wrong quantization rungs.
Release engineering has triaged the defect to **one single file**:

```
/app/sigdeck/windowing.py
```

You must repair that file so the whole package matches the frozen 3.1.0
interface spec (restated below). **This is a pinned hotfix branch: every
other file in the repository must remain byte-for-byte identical.** The
verifier checksums `sigdeck/__init__.py`, `sigdeck/codec.py`,
`sigdeck/constants.py`, `sigdeck/runner.py`, and `/app/input.csv` against
the release manifest and fails the run if even one byte of them changed.
In particular, the frozen constants in `sigdeck/constants.py` (the window
length and the ladder) must not be "tuned" — the fix belongs in the
windowing math, not in the constants.

You may create new scratch files elsewhere under `/app`, but nothing outside
`/app/sigdeck/windowing.py` may be modified or deleted.

## Interface spec (frozen, release 3.1.0)

Input CSV (first line `t,raw`): `t` is an integer sample tag, `raw` a hex
token decoded by `sigdeck.codec.decode` (16-bit two's-complement, optional
`0x` prefix, e.g. `0x0004` -> 4, `0xFFFE` -> -2, `0x0100` -> 256).

- `moving_rms(values, W)` returns one float per input sample. For index i
  the window is the **trailing** run of samples that ends **at and
  includes** i and contains at most `W` samples:
  `window(i) = values[max(0, i - W + 1) : i + 1]`.
  The current sample is always in its own window; near the start of the
  stream the window is simply shorter — **never padded**.
  `out[i] = sqrt(mean(v*v for v in window(i)))` rounded to **4 decimal
  places**.
- `quantize(x, ladder=None)` returns the largest rung `r` in the (ascending)
  ladder with `r <= x`. A value **exactly equal** to a rung maps to that
  rung (ties up, not down). Below the first rung, the first rung is
  returned.
- `sigdeck.runner.build_report` composes the report
  `{"window": WINDOW, "count": n, "rms": [...], "rung": [...]}` and must
  keep working unchanged once `windowing.py` is fixed.

Runner CLI (unchanged, used by the verifier):

```
python3 -m sigdeck.runner <input_csv> <output_json>
```

## Known symptoms (from the failed acceptance run)

- Early samples are pulled down as if the stream were zero-padded before its
  start, and every reported RMS lags the true trailing window by one sample.
- Reported RMS values have too few decimals.
- Values that land exactly on a ladder rung quantize to the rung *below*.

## How you will be graded

1. Checksums of all files other than `/app/sigdeck/windowing.py` must match
   the release manifest.
2. The verifier runs `python3 -m sigdeck.runner` on the supplied
   `/app/input.csv` and compares the JSON report to the reference report.
3. It then runs the same package, unchanged, on **hidden telemetry files**
   (shorter than the window, exact-rung ties, boundary cases) and compares
   each against its reference report.

All checks must pass for reward 1.0.
