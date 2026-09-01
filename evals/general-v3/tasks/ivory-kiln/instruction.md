# Transcribe the photographed checksum routine

A whiteboard snapshot from the "Ivory Kiln" batch pipeline was archived as
`/app/code.png`. It shows a short Python routine, `compute(n)`, photographed
off a wallboard: the photo is slightly rotated and noisy, and off-the-shelf
OCR mangles at least one of the lines (typically the loop body), so it must be
transcribed by eye. You must recover the routine's exact integer constants and
evaluate it.

## Environment

- Working directory: `/app`. It already contains `code.png` (the photograph)
  and `calib.json` (a JSON object holding the call argument `n`).
- Python 3.12 is available as `python3`. The image also ships `pillow`, `numpy`,
  `opencv-python-headless` and `pytesseract` (plus the `tesseract` binary) if
  you want to preprocess or machine-read the photo. No network access.
- Do not modify `/app/code.png` or `/app/calib.json`.

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:
   ```
   python3 /app/solve.py <photo_png> <calib_json> <output_json>
   ```
   It must work on **any** photograph of the same routine with different
   constants (the grader re-runs it on unseen photos).

2. `/app/answer.json` — the output your program produces on the provided
   fixtures:
   ```
   python3 /app/solve.py /app/code.png /app/calib.json /app/answer.json
   ```

## The routine shown in the photograph

Every photo shows the same seven-line function; only the integer constants
differ between photos:

```python
def compute(n):
    total = 0
    for i in range(L, U):
        total = total + i * i
    total = total * F
    total = total + n * S
    return total - K
```

`L`, `U`, `F`, `S`, `K` are non-negative integer literals rendered in the
photo. The value to output is the integer the routine returns when called as
`compute(n)` with `n` taken from `calib.json`.

For example, with `L=3, U=18, F=4, S=7, K=231, n=12` the routine returns
`6973` — but that is only an illustration; the shipped photo may differ.

## Output format

The output file must be valid JSON with exactly one key:

```json
{ "code_value": <int> }
```

## Constraints

- The verifier runs `/app/solve.py` **unchanged** on hidden photographs of the
  same routine with different constants and different `n`, so do not hard-code
  constants or answers. Your program may, however, rely on the routine having
  exactly the line structure shown above (loop body `total = total + i * i`,
  the two scaling/addition lines, and the subtraction in the return).
- Misreading any single character (e.g. one digit of `U`, or `*` vs `+`) changes
  the final value; the verifier compares the integer exactly.
- Write `/app/answer.json` for the visible fixtures before you finish.
