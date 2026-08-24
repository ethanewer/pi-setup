# Reductions from a printed algorithm sheet

In `/app` is a single image, **`algorithm.png`**. It shows a hand-drawn-style
pseudocode sheet titled **BRIEFCASE REDUCE** — two procedures, `REDUCE(line)`
and `MAIN`. This image is the **only** specification of the algorithm.

Your task:

1. **Transcribe it before coding.** Open `algorithm.png` and read every line of
   the pseudocode carefully (it is typeset in a monospace face for legibility).
   Do not guess — copy the steps exactly as printed.
2. **Mind the ambiguous operators.** The sheet uses `mod` and `div` for
   remainder and **truncating integer division** (both apply to unsigned, base-10
   integers). It also relies on expression grouping written with parentheses; do
   not drop or re-associate them.
3. **Implement it in Python 3** as `/app/briefcase.py` (standard library only).
4. **Validate against an independent calculation** before you finish (see the
   sample files below).

## Program contract (exact)

When run, `/app/briefcase.py` must:

- read its input from the file **`/app/input.txt`**, one record per line;
- write its output to the file **`/app/output.txt`**;
- treat `\n` and `\r\n` line endings the same and never emit a trailing blank
  line beyond the last newline.

**Input constraints (guaranteed by the harness):** every input line is either
empty or contains only lowercase letters `a`..`z` (no spaces, digits, or
punctuation). Consecutive lines need not be unique.

**Meaning:** a line is *eligible* if it is not blank **and** contains at least
one lowercase letter. For every eligible line, in input order, the algorithm
produces exactly one output line; blank lines produce nothing.

**Per-line computation (exactly as the sheet says):**

1. `acc := 0`.
2. Iterate characters left to right. For each character `ch`,
   `acc := acc + ( ord(ch) - ord('a') + 1 )`  (so `a`→1, `b`→2, …, `z`→26).
3. Fold repeatedly: while `acc >= 10`, set `n := acc`, set `acc := 0`, and while
   `n > 0`: `acc := acc + (n mod 10)`, `n := n div 10`. In other words replace
   `acc` by the sum of the decimal digits of the *previous* `acc`, and repeat
   until it is a single digit.
4. The line's result is the single character
   `chr(48 + acc)` — the digit `'0'`..`'9'` equal to the folded value (a folded
   value of `0` yields `'0'`, and so on).

**Format of `/app/output.txt`:** one result per eligible line, in input order,
each followed by a single newline. There is no header, no footer, and nothing
else.

## What is already in `/app`

```
/app/
  algorithm.png        # the pseudocode sheet (the only spec)
  sample_input.txt     # sample input for you to sanity-check against
  sample_output.txt    # expected output for sample_input.txt
```

Are provided. `briefcase.py` is created by you.

## Local validation (required before you finish)

Run:

```
python3 /app/briefcase.py        # reads /app/input.txt, writes /app/output.txt
```

To self-check, first copy `sample_input.txt` to `/app/input.txt`, run
`briefcase.py`, then confirm `/app/output.txt` differs same as `sample_output.txt`
(`diff -u`). Then **recompute the expected values by hand** for a couple of tiny
inputs (for example a one-letter line and a two-letter line) and confirm your
program agrees — do not simply trust your own translator against the sample.

## Hidden grading

The harness will overwrite `/app/input.txt` with its own test input (satisfying
the constraints above), run your `briefcase.py`, independently compute the
expected `output.txt` from the printed algorithm (its own calculation, separate
from yours), and compare **byte-for-byte**. Correctness of the digits, their
order, and the per-line format all count. There is no randomness.

Notes:

- Use only the Python 3 standard library. Do not read/parse `sample_output.txt`
  at runtime; it is only a convenience for you.
- The harness may reset the workdir; your program must hard-code the fixed
  paths `/app/input.txt` and `/app/output.txt`.
- If your interpretation of the paper disagrees with the reference, trust the
  printed pseudocode: `mod` is remainder, `div` is truncating integer division,
  `chr(48+acc)` with the folded value.
- The image is intentionally the only spec; re-open and re-read it if your
  output diverges from the independent calculation.