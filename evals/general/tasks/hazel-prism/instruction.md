# Prism Link — compressed renderer firmware

The Prism Link handset ships a tiny firmware module that renders two ASCII
"lenses" on a low-bandwidth link. The module's **source must be small enough to
survive transport compression**: it is stored as gzip, and the compressed image
of the source is what actually counts against the budget. A renderer that
sneaks the rendered pixel/character data in as string literals does not
compress well enough to ship — the module must **compute** every frame from
arithmetic alone.

## Deliverables (both required, exact paths)

1. `/app/frame.py` — a runnable Python 3.12 program (stdlib only) with the
   command-line interface:
   ```
   python3 /app/frame.py [mode] [rows cols]
   ```
   - `mode` is the literal token `mandel` or `julia` (default: `mandel`).
   - `rows` and `cols` are optional integers; if given, both must be given
     together. Defaults: **34 rows x 92 cols** for `mandel`,
     **36 rows x 84 cols** for `julia`.
   - It prints the frame to stdout: exactly `rows` lines, each exactly `cols`
     characters, newline-terminated (a trailing newline after the last line).

2. `/app/frame-sizes.json` — a JSON report of the real measured sizes of your
   `/app/frame.py`:
   ```json
   { "source_bytes": <int>, "gzip_bytes": <int> }
   ```
   where `source_bytes` is the byte length of `/app/frame.py` and
   `gzip_bytes` is `len(gzip.compress(open("/app/frame.py","rb").read(), 9))`.
   The verifier re-measures both numbers itself; the report must match exactly.

## Hard budget (checked on every verification)

- **Raw source cap:** `len(source) <= 900` bytes.
- **Compressed source cap:** `gzip_bytes <= 480`.
- **No embedded pixels:** no 16-character window containing a non-space
  character from any line of the *default-size* frames (`mandel 34x92` or
  `julia 36x84`) may appear anywhere in the source. In practice this makes
  storing the artwork in the source impossible; the frames must be computed.

## Render specification (byte-exact)

Let `RAMP = " .:-=+*#%@"` (index 0 = space, index 9 = `@`), and let
`rows`/`cols` be the frame dimensions. The character printed at row `r`
(`0 <= r < rows`) and column `c` (`0 <= c < cols`) is `RAMP[i]` with
`i = min(k * 9 // 40, 9)` where `k` is defined by the mode:

**mode `mandel`** — iterate the standard Mandelbrot escape:
```python
cr = -2.1 + 3.0 * c / (cols - 1)
ci = -1.2 + 2.4 * r / (rows - 1)
z = 0j
k = 0
while k < 40 and abs(z) <= 2.0:
    z = z * z + complex(cr, ci)
    k += 1
```

**mode `julia`** — iterate the Julia set for `c0 = -0.7 + 0.27015j`:
```python
zr = -1.5 + 3.0 * c / (cols - 1)
zi = -1.5 + 3.0 * r / (rows - 1)
k = 0
while k < 40 and zr * zr + zi * zi <= 4.0:
    zr, zi = zr * zr - zi * zi - 0.7, 2.0 * zr * zi + 0.27015
    k += 1
```

`k` is the number of completed iterations when the loop stops (so a point that
is already outside on the first test has `k = 0` and renders as a space).
The verifier reproduces this specification independently and compares the
output **byte for byte**, so follow it exactly (same loop order, same
comparisons, same integer floor-division for the ramp index).

## Generalization

The verifier re-runs your program unchanged on **hidden argument sets**
(e.g. `mandel 16 40`, `julia 44 90`, ...) with `rows, cols >= 8`, so the
renderer must be fully parameterized — do not special-case the default sizes
and do not hard-code any output content. Output must be deterministic.

## Constraints

- Python 3.12, standard library only; no network access.
- Do not modify this task's fixture files; your deliverables are
  `/app/frame.py` and `/app/frame-sizes.json`.
