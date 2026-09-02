# ashen-vane — PGM kernel-scoring CLI

The vision team needs a small **native binary** tool that scores a grayscale
image against a convolution kernel. Author the tool from scratch, compile it,
and leave the binary in `/app`. The grader runs your binary unchanged on
hidden inputs, so it must work on **any** files obeying the contracts below,
not merely on examples you have seen.

## Deliverables (both required)

1. `/app/bin/edgecheck` — a **native compiled executable** (an ELF binary; a
   `#!/...` script is not acceptable). The grader checks `file` output for ELF.
2. `/app/src/edgecheck.c` — the C source you compiled it from. It must be
   non-empty and buildable with `gcc`.

Compile with the installed toolchain, e.g.:

```
gcc -O2 -o /app/bin/edgecheck /app/src/edgecheck.c -lm
```

## Command-line contract (argument order is fixed)

```
/app/bin/edgecheck <weights-path> <image-path>
```

- **Argument 1 is the weights (kernel) file; argument 2 is the image file.**
  The program must read the arguments positionally and literally: it never
  inspects file contents to "auto-detect" which is which, and it must validate
  that argument 1 parses as a kernel file and argument 2 as an image file (so
  a swapped invocation is rejected — see below).
- Invoked with any number of arguments other than exactly 2: print the line
  `usage: edgecheck <weights-path> <image-path>` to **stderr** and exit with
  status **2** (nothing on stdout).
- If a file cannot be opened, or either file is malformed for its role, print
  a line starting with `error:` to **stderr** and exit with status **1**
  (nothing on stdout).
- On success print exactly one line to stdout of the form
  `score=<S>` where `<S>` is the score (below) formatted with **exactly two
  decimal places** (e.g. `score=42.00`, `score=0.75`), then exit **0**.

## Weights (kernel) file format

Line 1 is exactly a header:

```
kernel <K>
```

where `<K>` is an integer with **1 <= K <= 16**. Everything after the header
must be exactly **K*K** numeric tokens (row-major, K rows of K values),
separated by arbitrary whitespace; any extra non-whitespace content or any
non-numeric token makes the file malformed. Kernel values are real numbers and
may be negative, fractional, or in scientific notation (e.g. `-2`, `0.5`,
`1.5e0`).

## Image file format (ASCII PGM, `P2`)

The file is a whitespace-separated token stream in which a `#` begins a
**comment that runs to the end of the line** (comments may appear anywhere,
including mid-line, and must be ignored). The tokens are:

1. the magic token `P2` (anything else is malformed);
2. `width`, `height`, `maxval` — positive integers;
3. exactly `width*height` pixel values — integers with `0 <= p <= maxval`
   (a pixel outside that range, or a non-integer token, is malformed);
4. no further tokens (trailing whitespace is fine, extra tokens are not).

Tokens may span lines in any arrangement. Missing tokens or surplus tokens
make the file malformed.

## Scoring computation

Let `img[i][j]` be the pixel at row `i`, column `j` (0-based) and
`w[u][v]` the kernel value at kernel row `u`, column `v` (0-based, row-major).
Let `c = K / 2` using **integer floor division** (so `c = 1` for `K = 2` or
`K = 3`).

For every pixel `(i, j)` compute the filtered value with **replicated (clamped)
borders**:

```
acc = sum over u in 0..K-1, v in 0..K-1 of
      w[u][v] * img[clamp(i + u - c, 0, height-1)][clamp(j + v - c, 0, width-1)]
```

accumulating in double precision, u-major then v. The score is

```
S = sum over all pixels of |acc|
```

(fractional, printed as described above).

## Edge cases the grader probes

- **Swapped arguments** (image path first, kernel path second) must exit
  nonzero with **nothing on stdout**.
- **Wrong argument counts** (0, 1, or 3+ args) exit 2 with the usage line.
- **Missing files** exit 1 with an `error:` line.
- Kernels with `K = 1`, even `K = 2`, and larger odd `K`; negative and
  fractional kernel values; scientific-notation kernel tokens.
- PGM comments in odd places; pixel tokens spread over arbitrary lines.
- Malformed images (pixel above `maxval`, non-integer tokens, truncated or
  surplus pixel data) and malformed kernels (wrong header, wrong token count)
  → exit 1, no stdout.

## Constraints

- Standard C only; link against libc/libm. No external libraries.
- No network access. Do not wrap the logic in a shell or Python script — the
  deliverable must be the compiled ELF binary itself.
