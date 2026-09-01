# frost-latch — cold-chain shelf scanner

**Kettle Frost Logistics** runs cold-storage aisles instrumented with grayscale
thermal cameras. Each shelf row of a frame has to be scored against a
per-column calibration weight vector to find the hot and cold spots. You must
author a small C program from the spec below and leave a compiled, working
binary in `/app`.

## Deliverables (all three required)

1. `/app/shelfscan.c` — the C source of the scanner, written by you.
2. `/app/Makefile` — whose default target compiles `/app/shelfscan.c` into the
   binary `/app/bin/shelfscan` with `cc` (or `gcc`) and `-O2`. It must create
   the `bin/` directory if missing and support `make clean`.
3. `/app/bin/shelfscan` — the compiled binary, built and left in place.

Build it yourself (e.g. `make -C /app`) so the binary exists when you finish.

## CLI contract (fixed argument order)

```
shelfscan <weights-path> <image-path>
```

- **Argument order is fixed and literal:** argument 1 is the *weights* file,
  argument 2 is the *image* file. The program must not auto-detect or swap
  them; swapping the two paths must change the result for typical inputs.
- If the argument count is not exactly 2, print a usage line
  (`usage: shelfscan <weights-path> <image-path>`) to **stderr**, print
  nothing to stdout, and exit nonzero.
- If either file cannot be opened, print a brief error to **stderr**, print
  nothing to stdout, and exit nonzero.
- On success print the three result lines to stdout (below) and exit `0`.

## Weights file format

- Plain text. A `#` character starts a comment that runs to the end of the
  line (comment text is stripped before tokenizing).
- Tokens are separated by whitespace (spaces, tabs, CR, LF).
- Every non-empty token must be a real number matching exactly:
  `[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?` — e.g. `12`, `-3.5`, `2.5e3`,
  `7.`, `+.5`. A token with any other shape (e.g. `junk`, `1.2.3`, `1,5`,
  `nan`, `inf`, `0x10`) is an error: print a brief message to stderr, print
  nothing to stdout, exit nonzero.
- A weights file containing zero tokens (empty or comments only) is valid: the
  weight vector is empty.
- Weights are consumed in file order: `w[0], w[1], ...` as `double`.

## Image file format (PGM)

The image is a PGM grayscale file, either **P2** (ASCII) or **P5** (binary):

- Magic `P2` or `P5` followed by one whitespace byte.
- Then, separated by whitespace (a `#` comment may appear between header
  tokens and runs to end of line): `width`, `height`, `maxval`.
- `width >= 1`, `height >= 1`, `1 <= maxval <= 65535`; anything else is an
  error (stderr message, no stdout, nonzero exit).
- **P5:** after the single whitespace byte that follows `maxval`, the raw
  samples follow: `width*height` samples, **1 byte each** when
  `maxval < 256`, otherwise **2 bytes each, big-endian**, row-major
  (row 0 first, left to right). If fewer bytes than that remain, it is an
  error. Trailing extra bytes beyond the required samples are ignored.
- **P2:** `width*height` decimal sample tokens follow `maxval` as whitespace
  separated tokens (comments allowed). Fewer tokens than that is an error.
  Extra trailing tokens are ignored.
- Sample values are used **raw** (no normalization by maxval).

## Scoring (apply exactly)

Let `width`, `height` be the image dimensions, `px[r][i]` the raw sample of
row `r`, column `i` (0-based), and `n = min(len(w), width)`.

- `response[r] = sum_{i=0}^{n-1} w[i] * px[r][i]` — accumulate left to right
  in `double`. If the weight vector is empty, every response is `0.0`.
- `max` row = the **first** row index with the strictly greatest response.
- `min` row = the **first** row index with the strictly least response.
- `mean` = the sum of all `response[r]` (accumulated in row order, in
  `double`) divided by `height`.

## stdout (exactly three lines)

```
max <r> <response>
min <r> <response>
mean <response>
```

- `<r>` is the 0-based row index in decimal.
- `<response>` is formatted with exactly **4 decimal places** (`%.4f`, e.g.
  `1234.5000`, `-8.2500`).
- Each line ends with a single `\n`. Nothing else is printed to stdout.

## Grading

The verifier rebuilds the binary from your source via the Makefile, checks the
binary is a real ELF executable, and runs `/app/bin/shelfscan` on hidden
weights/image pairs that obey the formats above — including P2 and P5 images,
weights shorter and longer than the image width, a weights file with only
comments, big-endian 2-byte samples, tied rows (first-row tie rule), wrong
argument counts and unopenable files. It also runs the binary twice on the
same input and requires byte-identical stdout. Results must match an
independent reference implementation of the spec above.

## Constraints

- No network access at verify time; build only with what the image provides
  (`gcc`, `make`, `python3`).
- Keep the deliverables at the exact paths above; do not modify anything
  under `/tests`.
