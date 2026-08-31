# Pack a firmware release tree into a deterministic index and bundle

**Halvard Embedded** ships firmware releases as two artifacts built from a
release tree: a byte-stable *index* describing every member file, and a
*bundle* archive whose bytes must be identical no matter when, where, or by
whom the tree was packed. Two builds from the same tree must be
**byte-identical** — different file mtimes, different creation order, different
machines must not change a single output byte. Your job: author the packing
tool and produce the release artifacts from the shipped tree.

Work inside `/app`. **Do not modify** anything under `/app/fw_tree`.

## Environment

- Working directory: `/app`. It already contains the release tree
  `/app/fw_tree` (nested directories, text and binary files, unicode file
  names, an empty file). Python 3.12 is available; standard library only, no
  network.

## Deliverables (all required)

1. `/app/pack_index.py` — a runnable Python program: executable bit set
   (`chmod +x`), first line shebang `#!/usr/bin/env python3`, two subcommands:

   ```
   python3 /app/pack_index.py index <in_dir> <out_json>
   python3 /app/pack_index.py pack <in_dir> <out_zip>
   ```

2. `/app/index.json` — produced by running the `index` subcommand on
   `/app/fw_tree`.

3. `/app/bundle.zip` — produced by running the `pack` subcommand on
   `/app/fw_tree`.

## Member enumeration and ordering (the core contract)

- Enumerate all **regular files** under `<in_dir>` recursively (skip symlinks
  and any non-regular entry), recording paths relative to `<in_dir>` with `/`
  separators.
- Order members by the **UTF-8 byte sequence of the relative path** (plain
  codepoint/byte sort — `B.txt` < `Z.txt` < `a.txt` < `é.txt`; never
  locale-aware collation, never case-folding).
- **No host-identity fields anywhere**: outputs must never contain owner or
  group names/ids, user names, host names, wall-clock timestamps, or file
  mtimes.

### `index` subcommand

Write `<out_json>` as UTF-8 JSON with **exactly** these top-level keys:

```json
{
  "entries": [
    {"path": "…", "size": <int bytes>, "sha256": "<64 hex chars>"},
    …
  ],
  "format": "fw-bundle-index-1"
}
```

- One entry per member, in the sorted order above; `sha256` of the raw file
  bytes; entry objects carry **exactly** the keys `path`, `size`, `sha256`.
- Running the subcommand twice on the same tree must produce byte-identical
  JSON.

### `pack` subcommand

Write `<out_zip>` as a ZIP archive:

- Members are written in the sorted order above; **file members only** (no
  directory entries, no trailing-slash names).
- Every member must be created from a **fresh `zipfile.ZipInfo`** with
  `date_time` fixed to `(1980, 1, 1, 0, 0, 0)` and `compress_type` set to
  `ZIP_STORED`. Do **not** use `ZipFile.write()` or `ZipInfo.from_file()` —
  those copy host metadata (mtime-derived timestamps, permission bits from the
  local filesystem) and break byte-identity. Do not set any `extra` bytes, no
  per-member comments, and no archive comment.
- Each member's decompressed bytes must equal the file's raw bytes.
- Running the subcommand twice on the same tree must produce byte-identical
  ZIP files; running it on two copies of the same tree that differ only in
  file mtimes or creation order must also produce byte-identical ZIP files.

## Edge cases the grader probes (the tool must handle all of them)

- Trees whose names only sort correctly under plain byte order (uppercase vs
  lowercase, unicode names such as `é.txt`, names differing only after a
  shared prefix, e.g. `a/z.txt` vs `a/z2.bin`).
- An **empty tree** (no files at all): the index must have `"entries": []` and
  the bundle must be a valid ZIP with zero members.
- Binary files (containing NUL bytes and all 256 byte values) and empty files.
- Two copies of one tree with deliberately shifted mtimes and reversed
  creation order must yield identical index and bundle bytes.

## Constraints

- Standard library only; no network.
- The grader executes `/app/pack_index.py` unchanged on hidden trees, so
  implement the full contract — do not hard-code the shipped fixture.
- Do not read or write anything under `/tests`.
