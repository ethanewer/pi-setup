# slate-gauge — thermal-camera exposure gauge

The **slate** night-shift QA bench rates raw thermal frames. You must author a
small C program and leave a compiled, working binary in `/app`.

## Deliverables (both required)

1. `/app/src/gauge.c` — the C source of the gauge tool.
2. `/app/bin/gauge` — a native ELF executable **compiled from that source**
   (e.g. `gcc -O2 -o /app/bin/gauge /app/src/gauge.c`). It must be executable
   and must behave exactly as specified below. The verifier recompiles
   `/app/src/gauge.c` with the system `gcc` into a fresh binary and checks that
   the fresh build behaves identically to `/app/bin/gauge` — so the binary must
   be a genuine build of the source you leave behind.

## CLI contract (argument order is fixed)

```
/app/bin/gauge <weights-path> <image-path>
```

- **Argument 1 is the weights file, argument 2 is the image file.** The program
  reads the order literally and must never auto-detect or swap. Swapping the two
  paths changes the meaning of the invocation and must not silently succeed.
- If the program is invoked with **any number of arguments other than exactly
  two**, it must print the line
  `usage: gauge <weights-path> <image-path>`
  to **stderr**, print **nothing** to stdout, and exit with status `2`.
- If either file cannot be opened or parsed as specified below, print a brief
  one-line error to **stderr**, print **nothing** to stdout, and exit with
  status `1`.
- On success it prints **exactly one line** to stdout:
  `score=<R>` where `<R>` is the score formatted to **exactly 3 decimal
  places** (e.g. `score=32.000`, `score=-4.125`), followed by a newline, and
  exits with status `0`.

## Weights file format

Plain text. The whole file is split on whitespace runs (spaces, tabs, newlines)
into tokens.

- A token is **valid** iff it is a decimal real number with no leftover
  characters: optional `+`/`-` sign, then either digits with an optional
  fractional part (`12`, `-3.5`, `7.`) or a fractional form (`.5`), with an
  optional `e`/`E` exponent (`2.5e3`, `1E-2`).
- Anything else (`junk`, `0x10`, `NaN`, `inf`, `--3`, `1.2.3`, `1,5`) is an
  **invalid token** and is ignored entirely.
- The weights vector `w` is the list of valid tokens in file order (invalid
  tokens do not shift anything; they simply do not exist). Duplicates are kept.
- An empty or all-invalid weights file yields an empty `w`.

## Image file format (binary PGM, magic `P5`)

- The file must begin with the two bytes `P5`.
- After the magic, the header consists of three decimal integer tokens —
  `width`, `height`, `maxval` — separated by whitespace. Whitespace here is
  space, tab, carriage return, or newline. A `#` starts a **comment** that runs
  to the end of the line; comments may appear anywhere between header tokens
  (including immediately after `P5`) and are ignored.
- Constraints: `width >= 1`, `height >= 1`, `1 <= maxval <= 255`. All three
  tokens must be plain decimal digits with no sign or other characters.
- After the `maxval` token there is **exactly one** whitespace byte, then the
  raw raster: `width * height` bytes, one byte per pixel, row-major. If the
  file contains **fewer** than `width * height` raster bytes it is invalid.
  Any extra trailing bytes after the raster are allowed and ignored.
- Anything violating the above (wrong magic, ASCII `P2` images, `maxval` out of
  range, short raster, non-digit header tokens, …) makes the image **invalid**.

## Score computation

Let `p[0..N-1]` be the raster bytes (`N = width * height`) and let
`n = min(len(w), N)`.

```
R = sum_{i=0}^{n-1}  w[i] * (p[i] / maxval)
```

- Pixel values are normalized by `maxval` (division, floating point).
- If `n == 0` (empty weights, or an empty raster — impossible since
  `width,height >= 1` — or an empty/missing weights file) the score is `0.0`
  and the program prints `score=0.000`.
- Weights beyond `N` and pixels beyond `len(w)` are simply unused.

## Visible fixtures

`/app/fixtures/` contains two sample pairs you can test with:

- `weights.txt` + `frame.pgm`
- `weights_noisy.txt` + `frame_small.pgm`

## Constraints

- Toolchain available in the image: `gcc`, `make`, `python3`. No network at
  verify time.
- The verifier runs `/app/bin/gauge` **unchanged** on hidden weights/image pairs
  that follow the contracts above (including junk-token weights, truncated
  rasters, non-255 maxval, empty weights, invalid images, swapped argument
  order, and wrong argument counts), so do not hard-code the visible fixture
  contents.
- Keep the exact deliverable paths.
