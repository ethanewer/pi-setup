# Onyx handheld — boot-splash renderer under a shipping size ceiling

The Onyx handheld's bootloader pulls exactly one file over a 1200-baud boot
wire: the renderer source itself. The splash frame is far too large to ship
(its raw PNG-equivalent dump would never fit in the flash window), so the
**renderer program** is what ships — and its size is hard-capped: the
bootloader accepts the source only if its **gzip-compressed size is at most
`gzip_max` bytes** and its **raw size is at most `raw_max` bytes**. The source
must compute the frame from arithmetic alone: **embedding or encoding any of
the rendered pixel data in the source is a firmware-signing violation** (and
would blow the caps anyway).

## Deliverables (all required)

1. `/app/splash.py` — the renderer program:
   ```
   python3 /app/splash.py <spec.json> [out_file] [report_file]
   ```
   With no optional arguments it defaults to `out_file=/app/splash.txt` and
   `report_file=/app/frame-report.json`. It reads a render spec and writes:
   - the rendered frame to `out_file` (exact format below), and
   - a size report about **its own source file** to `report_file`.
2. `/app/splash.txt` — the frame your renderer produces for the shipped spec
   `/app/spec.json`:
   ```
   python3 /app/splash.py /app/spec.json /app/splash.txt /app/frame-report.json
   ```
3. `/app/frame-report.json` — the report produced by the same command.

**Do not modify `/app/spec.json`.**

## Render spec (JSON)

```json
{"width": 56, "height": 24, "ramp": " .:-=+*#%@",
 "kx": 3, "ky": 5, "kxy": 7, "mod": 13, "den": 3,
 "gzip_max": 400, "raw_max": 750}
```

## Frame format

`height` lines, each exactly `width` characters from the multi-character
ramp `ramp` (length `R = len(ramp) >= 2`), newline-terminated, no trailing
blank line beyond the final newline. The character at row `y` (0-based,
`0 <= y < height`) and column `x` (0-based, `0 <= x < width`) is

```
t   = kx*x*x + ky*y + kxy * ((x*y) mod mod)
idx = (t // den) mod R
chr = ramp[idx]
```

All spec values are non-negative integers (`mod >= 1`, `den >= 1`), `x*y`
means integer product, and all arithmetic is exact integer arithmetic.

## Size report (`report_file`)

JSON with exactly these keys:

```json
{"raw_bytes": <int>, "gzip_bytes": <int>,
 "gzip_max": <int>, "raw_max": <int>,
 "width": <int>, "height": <int>}
```

- `raw_bytes` — the byte size of the renderer's **own source file** (use
  `__file__` so it works no matter where the program is copied).
- `gzip_bytes` — the size of `gzip.compress(<source bytes>)` with default
  settings (standard library `gzip` module, default compression level).
- `gzip_max` / `raw_max` / `width` / `height` — echoed from the spec.

## Firmware-signing rules (verified byte-exactly by the plant)

The source `/app/splash.py` must satisfy **all** of the following for every
spec it is run against:

1. **gzip cap** — `gzip_bytes <= spec["gzip_max"]` and
   `raw_bytes <= spec["raw_max"]`.
2. **No embedded rows** — no full output line (a `width`-character row of the
   frame) may appear anywhere in the source text.
3. **No embedded pixel runs** — no run of **16 or more consecutive characters
   taken from any output row** may appear anywhere in the source text. The
   frame must come from the arithmetic, not from data smuggled into the
   program. (Rule 2 is implied by this for rows of width >= 16, but holds for
   narrow frames too.)

## What the plant re-runs

The plant re-runs `/app/splash.py` unchanged on **hidden render specs** that
follow exactly the schema above — different dimensions (including very wide,
tall, and thin frames), different ramps and coefficients, the same caps — and
checks the rendered frame byte-for-byte, both size caps on your source, the
anti-embedding rules, and that the report agrees with reality. A renderer
that hard-codes the shipped spec's numbers (e.g. a formula tuned to one
constant set, or special-cased dimensions) will fail. Keep the program
generic and small.

## Constraints

- Python 3.12 standard library only; no network at verify time.
- The verifier invokes your program with all three paths given explicitly;
  the defaults above are for local sanity checking.
- Deterministic: same spec in, byte-identical frame out, every run.
