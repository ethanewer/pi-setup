# Repair a broken native vector extension

You are given a small CPython extension, `snapvec`, which folds an array of
unsigned 32-bit integers into a deterministic 8-character lowercase hex
checksum. The C source has a single indexing defect: the loop does not visit
every element, so the reported checksums only cover part of each vector. Your
job is to diagnose and fix the defect, build the extension as a real compiled
module, and drive the supplied harness to produce a checksum report.

## Provided files under `/app`

- `/app/native.c` — the C source exposing `snapvec.checksum(seq)`. **This is the
  file you repair.** The defect is an index-advance / stride bug in the `for`
  loop inside `snapvec_checksum`: it must advance by exactly one index and visit
  every element once. Keep the mixing constants, the FNV-1a offset basis, and
  the overall folding scheme unchanged; do not replace the implementation with
  pure Python.
- `/app/setup.py` — the setuptools build script that builds the `snapvec`
  extension from `native.c`. Leave it as-is unless it is provably wrong.
- `/app/runner.py` — the data-driven harness (correct as shipped). It imports
  the compiled `snapvec` module, reads an input JSON, folds each vector with
  `snapvec.checksum(...)`, and writes a report. Do not replace it with a
  hardcoded table of answers.
- `/app/bench.json` — the supplied visible input. **Read-only input data; do
  not modify it.**

## Deliverables

The three files the verifier checks are:
`/app/native.c` (repaired C source), `/app/setup.py` (packaging), and
`/app/runner.py` (the data-driven harness). Complete the following by doing the
real work:

1. Repair `/app/native.c` so `snapvec.checksum` folds **every** element of the
   sequence, in order, exactly once (index `i` from `0` to `n-1`, with the
   position-mixing term `(i + 1) * 2654435761` applied each step).
2. Build the module into `/app` so it can be imported, by running the build:
   `python3 /app/setup.py build_ext --inplace` (run from `/app`).
3. Produce a report by RUNNING the harness:
   `python3 /app/runner.py --input /app/bench.json --output /app/report.json`.

The verifier will independently rebuild the extension from your `/app/native.c`
and re-run `runner.py` on fresh, hidden inputs, so your repair must work on ANY
input that follows the documented contract — not just `/app/bench.json`.

## Input format

The input JSON is either an array of vectors or an object `{"vectors": [...]}`.
Each vector is a (possibly empty) JSON array of unsigned integers in
`0 .. 2**32 - 1`.

## Output format

`runner.py` writes a JSON report:

```json
{ "n_vectors": <int>, "checksums": ["<8 hex>", ...] }
```

with exactly one lowercase 8-hex checksum per input vector, in order.

## Expected visible result

For `/app/bench.json` a correct repair yields `n_vectors = 4` and checksums:

```
["1e7252b8", "a4d6889c", "8b9e3385", "11f28c3e"]
```

Sanity-check against these before finishing.

## Edge cases hidden checks will probe

Make your repair handle all of these containers of the contract:

- **Empty vector**: folding zero elements returns the FNV-1a offset basis
  trimmed to the low 32 bits, i.e. `84222325`.
- **Single-element vector**: index 0 folds exactly once.
- **Even- and odd-length vectors**: the defect is a stride-2 loop that silently
  drops odd indices; hidden inputs use lengths 2, 3, 4 and 5 so that a wrong
  stride changes the checksums, while a correct repair does not.
- **Values at the 32-bit ceiling**: `4294967295`, `2147483648`, etc. accepted
  (elements are masked to 32 bits).
- **Repeated and zero-heavy vectors** (`[5,5,5,5,5]`, `[0,0,0,0,0,0,0]`):
  exercise the position weighting and the fold state.

## Machine notes

Single container; network is unavailable during verification. Work offline.
There is no GUI.