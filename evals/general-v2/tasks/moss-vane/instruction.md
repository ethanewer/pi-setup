# moss-vane — fixed-order grayscale scorer

Vane Instruments flys a tiny on-device scorer on its environmental sensors. The
firmware team needs the scoring stage delivered as a **native binary** with a
**fixed, literal argument order**: the weights file is always argument 1 and the
grayscale image is always argument 2. The program must never inspect file
contents to guess which file is which — it reads the arguments in the order
given, period.

You author the C source yourself and compile it with the preinstalled `gcc`.

## Deliverables (both required)

1. `/app/bin/infer` — a native ELF executable (not a script), built from your
   source, e.g.:
   ```
   gcc -O2 -o /app/bin/infer /app/src/infer.c
   ```
2. `/app/src/infer.c` — the C source of the scorer. The verifier **recompiles
   it from scratch** with `gcc -O2` and requires the rebuilt binary to behave
   identically to your shipped binary, so the source must be the real thing.

## CLI contract

```
/app/bin/infer <weights-path> <image-path>
```

- Argument 1 is the **weights** file, argument 2 is the **image** file, in that
  order, always. Swapping the arguments must not be auto-corrected: the program
  parses argument 1 as weights and argument 2 as an image, literally.
- Exactly two arguments are accepted. With any other argument count, print
  `usage: infer <weights-path> <image-path>` to **stderr**, exit with status
  **2**, and print nothing to stdout.
- If the weights file cannot be opened: print a brief error to stderr, exit
  **1**, nothing to stdout.
- If the image file cannot be opened: print a brief error to stderr, exit
  **1**, nothing to stdout.
- Any malformed input (below) → brief error to stderr, exit **1**, nothing to
  stdout.

## Weights file format

- Plain text. A `#` starts a comment that runs to the end of the line;
  comments may appear anywhere.
- Tokens are separated by arbitrary whitespace. Every token must be an
  optionally-signed decimal integer: an optional `+` or `-` followed by one or
  more digits (e.g. `7`, `-12`, `+3`).
- If any token violates that rule (e.g. `3.5`, `12x`, `--4`), the weights file
  is malformed → exit 1.
- Let `w[0..K-1]` be the tokens in file order. Weights at index **>= 16 are
  ignored**. Missing weights (K < 16) behave as weight 0.

## Image file format (ASCII PGM, magic `P2`)

- The first token must be the magic `P2`.
- Then, in order: `width`, `height`, `maxval` — decimal integers with
  `width >= 1`, `height >= 1`, `1 <= maxval <= 65535`.
- `#` comments are allowed anywhere whitespace is allowed (including inside
  the header and between pixel values).
- Then exactly `width * height` pixel values, each an integer with
  `0 <= pixel <= maxval`.
- After the pixels, only whitespace/comments may remain; any further token
  makes the file malformed.
- Any violation (wrong magic, bad header value, out-of-range dims/maxval/
  pixel, too few pixels, trailing token) → exit 1.

## Scoring (deterministic, pure integer — no floating point)

- Partition the image into a **4x4 grid** of blocks, row-major. Block
  `(br, bc)` with `br, bc` in `0..3` covers rows
  `[floor(br*H/4), floor((br+1)*H/4))` and columns
  `[floor(bc*W/4), floor((bc+1)*W/4))`. A range may be empty (possible when
  `H < 4` or `W < 4`); an empty block has block sum 0.
- The feature for block index `k = 4*br + bc` is its **block sum** `S_k` (the
  sum of the pixel values in the block, an integer).
- `score = sum over k in 0..15 of w[k] * S_k`, with `w[k] = 0` when `K <= k`.
  Compute in 64-bit signed integer arithmetic; the hidden inputs never
  overflow int64.
- `class` is `POS` if `score > 0`, `NEG` if `score < 0`, `ZERO` if
  `score == 0`.

## Output (on success, exit 0) — exactly two lines on stdout

```
score=<score>
class=<POS|NEG|ZERO>
```

Example (the shipped smoke fixture, `/app/fixtures/weights.txt` +
`/app/fixtures/image.pgm`): the correct output is exactly

```
score=-8
class=NEG
```

## Constraints

- `gcc` is preinstalled; no network access is needed or possible at verify
  time; standard C library only.
- Do not modify `/app/fixtures/weights.txt` or `/app/fixtures/image.pgm`.
- The verifier runs your binary **unchanged** on hidden weights/image pairs
  that obey the formats above (including comment-laden files, images of
  arbitrary sizes, >16 weights, missing weights, and malformed inputs that
  must fail with nonzero exit and empty stdout). Do not hard-code to the
  fixture contents.
