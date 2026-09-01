# Reconstruct the original tree from a cratepack store

A directory tree was repacked by the `cratepack` archiver into a flat **crate
store**: every original file was cut into fixed-size chunks, the chunks were
scattered across a set of bucket blobs in an arbitrary order, and a manifest
records where every chunk lives. Your job is to write the **unpacker** that
round-trips a store back into the exact original tree — identical file names,
identical directory nesting, byte-identical content.

Work only in `/app`. Do not modify anything under `/app/store` (it is the
read-only input). Do not read `/tests` or `/solution`.

## Provided input

- `/app/store/` — the visible crate store: `manifest.json` plus bucket blobs
  `bucket-0.bin` ... `bucket-7.bin`.

## Deliverables (both required)

1. `/app/unpack.py` — a self-contained Python 3 CLI tool:

   ```
   python3 /app/unpack.py --store <store_dir> --out <out_dir>
   ```

   It must work on **any** crate store conforming to the format below, not
   just the supplied one.

2. `/app/unpacked/` — the result of running your tool on the visible store:
   ```
   python3 /app/unpack.py --store /app/store --out /app/unpacked
   ```

## Crate store format

`manifest.json` is a JSON object:

```json
{
  "format": "crate-v1",
  "chunk_size": 1024,
  "buckets": 8,
  "files": [
    {
      "path": "docs/notes.txt",
      "size": 2400,
      "sha256": "<64 lowercase hex>",
      "chunks": [
        {"bucket": 5, "offset": 0, "length": 1024},
        {"bucket": 0, "offset": 1024, "length": 1024},
        {"bucket": 5, "offset": 1024, "length": 352}
      ]
    }
  ]
}
```

- `chunk_size` and `buckets` are positive integers; bucket blobs are named
  `bucket-<i>.bin` for `i` in `0 .. buckets-1` and hold concatenated chunk
  payloads.
- Each file entry lists, **in original file order**, the chunks that tile the
  file: chunk `k` covers bytes `[k*chunk_size, min((k+1)*chunk_size, size))`
  of the original file and is stored in bucket `bucket` at byte `offset` with
  the given `length`. Chunks of one file may live in **any** bucket in **any**
  relative position — the manifest order is the only authority.
- `sha256` is the digest of the **complete original file bytes**;
  `size` is its exact byte length.

## Required behavior

1. **Validate before writing anything.** Read and validate the whole manifest
   and all chunk data first. The reconstruction must satisfy, for every file:
   the assembled byte length equals `size`, and the SHA-256 of the assembled
   bytes equals `sha256`. If **anything** is inconsistent — a missing/short
   bucket blob, an offset or length reaching past the end of a bucket, a
   digest or size mismatch, a malformed or unsafe manifest — print a clear
   error to stderr and exit **non-zero without writing any output file**
   (do not leave a partial tree).
2. **Path safety.** Every `path` must be a relative path using `/` separators
   with no empty, `.`, or `..` component and no leading `/`. Anything else
   (including paths that would escape the output directory) is invalid and
   must be rejected as in rule 1. Duplicate paths are invalid too.
3. **Reconstruct exactly.** On success, create `<out_dir>` (if needed) and
   write every file at its manifest path, byte-identical, recreating nested
   directories. Files with size 0 (zero chunks) must exist as empty files.
   Print one line to stdout (`UNPACKED <n>` where `<n>` is the number of
   files) and exit **0**.

## Edge cases the hidden grader probes

- Files larger than one chunk whose chunks are scattered across several
  buckets (reassembly must follow manifest order, not bucket order).
- A file whose size is an exact multiple of `chunk_size`, and one that is one
  byte over.
- **Empty files** (zero chunks) that must still appear in the output.
- Binary content containing every byte value 0..255 (do not treat input as
  text).
- Deeply nested directories and many small files.
- **Corrupt stores** (e.g. a manifest digest that does not match the chunk
  data) must exit non-zero and write nothing.
- **Unsafe manifests** (a path containing `..`) must be rejected with a
  non-zero exit and nothing written outside — or inside — the output.

## Constraints

- Python 3.12 standard library only; no network access.
- The verifier reruns `/app/unpack.py` unchanged on hidden stores and checks
  the produced trees file-by-file (name set, sizes, SHA-256 digests), so no
  hard-coding to the supplied store.
