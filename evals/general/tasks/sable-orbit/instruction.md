# Auction settlement — objective extraction

You are on the settlement desk of an auction house. The working directory is
`/app`. It contains the settlement report fixture `/app/settlement.json`
(do not modify it). Everything else must be created by you.

The desk needs a small, reusable extraction tool plus the result it produces
on the provided fixture. The grading harness later runs your program
unchanged on *fresh* settlement reports you have never seen, so write it
generically against the contract below — never hard-code the fixture values.

## Deliverables (both required)

1. `/app/solve.py` — an executable Python 3 program (standard library only)
   with this interface:

   ```
   python3 /app/solve.py <report.json> <out.txt>
   ```

   It must:
   - read the JSON report from `<report.json>`;
   - isolate the value at `objective.reported` (ignore all sibling fields
     such as `baseline` or `projected`, and all other top-level keys);
   - compute the **integer part (floor)** of that value;
   - write to `<out.txt>` **exactly** the decimal digits of that integer
     followed by a single trailing newline — no spaces, no sign for
     non-negative values, no extra lines, nothing else;
   - print the integer on stdout;
   - exit `0`.

2. `/app/answer.txt` — the output produced by **running** your program on the
   provided fixture:

   ```
   python3 /app/solve.py /app/settlement.json /app/answer.txt
   ```

## Report format

`report.json` is a JSON object. The `objective` key holds an object whose
`reported` field is a **non-negative number** (it may be a decimal fraction,
an already-integral value, or written in exponent notation such as `9.18e3`).
All other fields (ids, names, percentages, `objective.baseline`,
`objective.projected`, …) are decoys that must be ignored.

## Edge cases your program must handle

These are probed by the grader on hidden reports, so the program must be
correct on all of them:

- fractional values floor **down**: `73804.62` → `73804`;
- values already integral (including JSON integers) pass through unchanged;
- exponent notation in the JSON source: `9.18e3` → `9180`;
- values smaller than one: `0.75` → `0`;
- very large values must not lose precision.

The output file is compared **byte-for-byte**: an extra blank line, leading
whitespace, or a float-formatted value (`73804.0`) is a failure.

## Constraints

- No network access; Python 3 standard library only.
- Do not modify `/app/settlement.json`.
