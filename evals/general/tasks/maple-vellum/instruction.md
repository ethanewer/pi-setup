# Reassemble a resharded chunk-store back into the original tree

A directory tree was "resharded" by an archiving tool: every file was cut into
fixed-size chunks, each chunk was hashed with SHA-256, and identical chunks
were stored **once** (deduplicated across the whole tree). A single manifest
records which chunk sequence makes up each original file. Your job is to write
the restorer that reverses this process exactly.

## Environment

- Working directory: `/app`. It already contains the resharded store
  `/app/store`. Python 3.12 is available as `python3`.
- **Do not modify anything under `/app/store`** (the verifier checks the
  store is byte-identical to how it was shipped).
- Do not read `/tests` or `/solution`.

## The resharded store format

```
<store>/
  manifest.json
  blobs/<first-2-hex-chars>/<64-lowercase-hex-sha256>
```

`manifest.json` is:

```json
{
  "version": 1,
  "chunk_size": 512,
  "hash": "sha256",
  "dirs": ["docs", "src", "src/util", "assets", "assets/tmp"],
  "files": {
    "README.md": {"size": 1686, "chunks": ["<hex>", "<hex>", "<hex>", "<hex>"]},
    "src/util/empty.py": {"size": 0, "chunks": []}
  }
}
```

Semantics (this is the exact contract of the tool that produced the store):

- Each original file's bytes were split into consecutive chunks of at most
  `chunk_size` bytes (the final chunk may be shorter). Every chunk was hashed
  with SHA-256 and stored at `blobs/<digest[:2]>/<digest>`.
- **Chunks are deduplicated**: the same digest may appear in many files'
  `chunks` lists (duplicate files share every chunk; files sharing a prefix
  share their leading chunks), but each digest is stored exactly once.
- `files` maps an original relative path (POSIX-style, relative to the tree
  root) to `{"size": <total byte count>, "chunks": [<digest>, ...]}` in order.
- An **empty original file** has `"size": 0` and `"chunks": []` — it must still
  be recreated as an empty file.
- `dirs` lists **every directory** of the original tree (parents included).
  Some listed directories were empty and contain no files — they must still be
  recreated as empty directories.
- File and directory names may contain spaces and non-ASCII characters.

## Deliverables (both required)

1. `/app/reassemble.py` — a standalone Python 3 program:

   ```
   python3 /app/reassemble.py --store <store_dir> --out <out_dir>
   ```

   It must reconstruct the complete original tree under `<out_dir>` (creating
   the directory if needed):
   - Every directory listed in `manifest.dirs` exists in the output (including
     empty ones), and every original file exists at its exact relative path
     with **byte-identical content**.
   - Verify integrity while restoring: each blob's bytes must hash (SHA-256)
     to exactly its digest (the blob path/file name), and each reassembled
     file's length must equal its manifest `size`. On any mismatch, missing
     blob, unreadable/invalid manifest, or unsafe path (absolute path or any
     `..` path component), print a clear error to **stderr** and exit
     **non-zero** — do not write a wrong tree.
   - On success exit `0` and print a one-line summary to stdout (any format).
   - Standard library only; must work on **any** store conforming to the
     format above, not just the shipped one. Repeated digests within one
     file's `chunks` list are valid and must be honored.

2. `/app/restored` — the tree you restore from the shipped `/app/store`:

   ```
   python3 /app/reassemble.py --store /app/store --out /app/restored
   ```

   The verifier checks `/app/restored` file-for-file (exact path set, exact
   directory set, SHA-256 of every file) against the ground truth of the tree
   that was resharded into `/app/store`.

## Hidden verification

The verifier also runs `/app/reassemble.py` unchanged on **hidden stores**
produced by the same tool: varied tree shapes, multi-chunk binary files,
whole-file duplicates, shared-prefix files, one chunk referenced by many
files, empty files, empty directories at several depths, unicode/space names,
and one intentionally **corrupted** store (a blob whose bytes do not hash to
its digest) on which your program must exit non-zero. Any name or byte
mismatch, or a missing empty file/directory, fails the reconstruction
assertion.

## Constraints

- No network at verify time; standard library only.
- Work offline, single container.
