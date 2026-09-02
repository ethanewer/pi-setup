# Streaming byte-offset text editor

_Build a tool that applies a list of edits to a large UTF-8 text file without
loading the whole source into memory, then run it on the provided inputs._

## Inputs (provided, in `/app`)

- `/app/source.txt` — a UTF-8 text file (may be large; contains multibyte chars).
- `/app/edits.json` — a JSON array of edit objects `{"start": int, "end": int, "text": str}`.

## Deliverables (write all three under `/app`)

1. `/app/edit_stream.py` — a **reusable command-line tool** with exactly this
   usage (all four arguments are paths):

   ```
   python3 /app/edit_stream.py SOURCE EDITS OUT_TXT OUT_MANIFEST
   ```

   It reads the file at `SOURCE`, applies the edits from `EDITS`, writes the
   edited result to `OUT_TXT`, and writes a JSON manifest to `OUT_MANIFEST`.
2. `/app/edited.txt` — the result of running the tool on `/app/source.txt`
   and `/app/edits.json`.
3. `/app/manifest.json` — the manifest produced for that same run.

The tool must be a general program: it must work on **any** valid input file
(even ones gigabytes large) following the contract below — the verifier runs
it on fresh hidden inputs.

## Tool contract (edge cases the hidden cases probe)

Byte offsets are **raw UTF-8 byte offsets in the original `SOURCE`** (0-based,
`end` exclusive). Replace `SOURCE[start:end]` with the UTF-8 bytes of `text`.

- `start`/`end` refer to bytes, **not** code points. Multibyte characters
  (e.g. a 2-byte `é`) span 2 bytes; an agent that counts code points will get
  boundaries wrong whenever a multibyte char precedes an edit.
- Edits are non-overlapping: for every pair, sorted by `end` of the previous,
  `next.start >= previous.end`. The order of the array does not matter; treat
  it as a set.
- Each edit must satisfy `0 <= start < end <= len(SOURCE)`. `text` may be empty
  (a deletion) or longer than the replaced range (an insertion), and may
  contain multibyte characters.
- Non-edit source bytes are preserved **verbatim** (byte-for-byte).
- The manifest JSON has exactly the keys:
  `{"sha256": "<hex-256 of OUT_TXT>", "byte_length": <byte count of OUT_TXT>}`.

### Required error behaviour (malformed input)

Valid edits form a non-overlapping, in-bounds set as above. If `EDITS` is
malformed in **any** way (not a JSON list, non-object entry, missing/extra
keys, non-integer start/end, non-string text, `start >= end`, negative start,
`end > len(SOURCE)`, or overlapping/ranges-out-of-order), the tool must print
an error to standard error and exit with a **non-zero** status. It must not
leave a partial output file in that case.

### Required streaming behaviour

`SOURCE` may be very large (hundreds of MB). The tool must **not** load the
whole source into memory; read it in bounded-size chunks and stream bytes to
`OUT_TXT` while hashing in the same pass. A large-file hidden case exists.

An empty source with an empty edits array, and a source with no matching
edits, are both valid and yield an empty/no-op result respectively.

## What must NOT be modified

`/app/source.txt` and `/app/edits.json` are inputs. Do not modify their bytes.
Run your tool so that it reads them; the verifier checks they are unchanged
afterwards.

## Note

You may not read or rely on any precomputed answer; produce `edited.txt` and
`manifest.json` by actually running your tool on the given inputs.