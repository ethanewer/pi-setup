# Segment the observatory blob under the storage quota

The Ridgecrest observatory stores each night's sensor dump as one large binary
blob. The archive gateway enforces a **per-object size quota**, so the blob must
be fragmented into segment files that each fit under the quota — and every
segment must be **self-describing** (carry its own integrity header) so the
reassembly tool can detect corruption. You will build that tooling.

## Environment

- Working directory: `/app`. It already contains the input blob
  `/app/snapshots.blob` (200,000 bytes).
- Python 3.12 is available as `python3`. Standard library only.
- **Do not modify `/app/snapshots.blob`.**

## Deliverables (all three required)

### 1. `/app/segmenter.py`

A plain Python 3 program with this two-command interface:

```
python3 /app/segmenter.py pack <input> <cap> <outdir>
python3 /app/segmenter.py merge <outdir> <output>
```

**`pack`** fragments `input` into self-describing segment files:

- `<cap>` is the **maximum byte size of each segment file** (header included).
- If `<input>` does not exist, print `pack: no such file: <input>` to stderr and
  exit non-zero without writing anything.
- `<cap>` must be a positive integer; otherwise print
  `pack: invalid cap: <cap>` to stderr and exit non-zero without writing
  anything. If `cap` is a positive integer but **smaller than 84** (i.e. it
  cannot hold the fixed 83-byte header plus at least one payload byte), print
  `pack: cap too small: <cap>` to stderr and exit non-zero without writing
  anything.
- Every segment file is named `seg_%06d.bin` (zero-padded width 6, ascending
  from 0). Each segment file contains, in order:
  1. an 83-byte header line: `SEG\t<i>\t<K>\t<hexdigest>\n` where `<i>` is the
     segment index (`%06d`), `<K>` the total number of segments (`%06d`), and
     `<hexdigest>` the lowercase 64-char SHA-256 of **this segment's payload
     bytes** — so the full header line is exactly
     `len("SEG\t" + "%06d" % i + "\t" + "%06d" % K + "\t") + 64 + 1 = 83` bytes;
  2. the segment's **payload**: raw bytes of the input. Every segment file is
     therefore at most `cap` bytes; each payload is
     `cap - 83` bytes except the last, which holds the remaining bytes
     (`0 < remaining <= cap - 83`).
- The number of segments is `K = ceil(S / (cap - 83))` where `S` is the input
  size. An **empty input (S = 0) yields zero segment files** (only the index).
- Also write `outdir/segments.json` — the reassembly index:
  ```json
  {"format": "SEG/1", "input": <basename of input>, "size": <S>,
   "cap": <cap>, "segments": <K>, "header_len": 83,
   "digest": <lowercase sha256 hex of the whole input>}
  ```
- Create `outdir` if missing; if it exists, remove any stale `seg_*.bin` files
  from previous packs before writing.

**`merge`** reassembles the segments back into the original bytes:

- Read `outdir/segments.json` (missing or unreadable → print a clear error to
  stderr, exit non-zero, write nothing).
- For each segment index `0..K-1` in order: the file `seg_%06d.bin` must exist
  (else error, exit non-zero); its 83-byte header must parse and match the
  expected index and total count (else error, exit non-zero); the SHA-256 of
  the payload must equal the digest in the header (else error, exit non-zero).
- Concatenate the payloads in order; the result must be exactly `size` bytes
  and its SHA-256 must equal the index `digest` (else error, exit non-zero).
- Write the bytes to `<output>` (overwriting if present). Reassembling a pack
  of a blob must reproduce the original bytes **exactly**.
- Any failure path must exit non-zero and must not write the output file.

### 2. `/app/segments/segments.json`

Produce the visible-case artifacts by running:
```
python3 /app/segmenter.py pack /app/snapshots.blob 65536 /app/segments
```
`/app/segments/segments.json` is the index written by that run (the segment
files `/app/segments/seg_0000*.bin` must also be present).

### 3. `/app/snapshots.restored`

Prove the round trip on the visible case by running:
```
python3 /app/segmenter.py merge /app/segments /app/snapshots.restored
```
It must be byte-identical to `/app/snapshots.blob`.

## What the grader checks

The grader re-runs your `/app/segmenter.py` on **hidden inputs** you have not
seen: blobs of assorted sizes (including an empty blob, sizes exactly equal to
and one byte above the per-segment payload capacity, tiny quotas, and a quota
below 84). For each it checks the pack is within quota and correctly indexed,
then merges and byte-compares with the original. It also tampers with segment
copies (removes a segment, flips payload bytes) and requires `merge` to reject
them with a non-zero exit and no output file. Your tool must be general —
parameterized by the arguments above — not hard-coded to the visible blob.

## Constraints

- Work under `/app` only. Do not modify `/app/snapshots.blob`.
- `/app/segmenter.py` must use only the Python standard library.
