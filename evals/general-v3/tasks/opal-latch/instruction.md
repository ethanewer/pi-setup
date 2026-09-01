# Restore an exact file tree from a chunk vault

A directory was processed by an offline packing tool ("vault-pack"): every
file of an original file tree was split into fixed-size chunks, identical
chunks were deduplicated into content-addressed blobs, and an index recorded
the layout. The result is a **reshard vault** directory. Your job is to write
one reusable Python program that restores the original file tree **in place,
exactly** — every original file name and every original byte — from such a
vault.

## Environment

- Working directory: `/app`. It already contains a sample vault at
  `/app/data/` (produced by the same tool and format documented below).
  Python 3.12 is available as `python3`.
- **`/app/data/` is read-only reference input.** Its contents are checked at
  verification time. While developing, always run your program on a *copy*
  (e.g. `cp -a /app/data /tmp/vault`), never on `/app/data` itself.
- Do not read `/tests` or `/solution` (they are not present during your work
  anyway).

## Deliverable

`/app/restore.py` — a self-contained Python 3 program (standard library only):

```
python3 /app/restore.py <vault_dir>
```

Given a vault directory it must reconstruct the original tree **inside
`<vault_dir>` itself** (in place) and then remove the vault artifacts, so
that afterwards `<vault_dir>` contains exactly the original tree: same
relative file names, same nested directories, same bytes, and nothing else.

## Vault format (what vault-pack produced)

A vault directory contains exactly two entries:

- `index.json` — the layout index:
  ```json
  {
    "version": 1,
    "chunk_size": 96,
    "digest": "sha256",
    "entries": [
      {"path": "docs/readme.txt", "size": 211, "chunks": ["<64 lowercase hex>", "..."]},
      {"path": "empty.lock", "size": 0, "chunks": []}
    ]
  }
  ```
- `blobs/` — one file per **unique** chunk, named `<64-hex-sha256>.blob`,
  holding exactly that chunk's raw bytes. Identical chunks (within a file or
  across different files) are stored **once** and referenced many times.

Chunking rules:

- Each original file's bytes are split sequentially into `chunk_size`-byte
  chunks; only the final chunk of a file may be shorter than `chunk_size`.
- An empty file has `"size": 0` and an empty `chunks` list; it must still be
  recreated (as an empty file).
- `entries[i].size` is the original file's exact byte length; concatenating
  the chunk blobs of an entry in list order must reproduce exactly `size`
  bytes.
- `path` values are relative to the vault root, use `/` separators, may nest
  arbitrarily deep, and never begin with `/`, end with `/`, or contain a `..`
  component. Parent directories are implied and must be created.
- Entries appear in no guaranteed order and must not be assumed sorted.

## Program behavior

1. Read and parse `<vault_dir>/index.json`. Validate the header
   (`version == 1`, integer `chunk_size > 0`, `digest == "sha256"`) and every
   entry (`path`/`size`/`chunks` well-formed as above, every chunk hash
   64 lowercase hex digits, every blob present and no longer than
   `chunk_size` bytes, concatenated length exactly `size`). If anything is
   inconsistent or missing, print a clear error to stderr and exit non-zero —
   restore nothing rather than restoring something wrong.
2. Write every original file to `<vault_dir>/<path>`, creating parent
   directories as needed.
3. Only after **all** entries have been restored successfully, delete the
   vault artifacts `<vault_dir>/blobs/` (recursively) and
   `<vault_dir>/index.json`.
4. Exit 0 on success. `<vault_dir>` must now contain exactly the original
   tree and nothing else — no leftover `blobs/`, no `index.json`, no temp
   files.

## Edge cases the hidden verifier probes

The verifier copies fresh vaults to scratch directories, runs
`/app/restore.py` on the copy, and requires the restored tree to equal the
original tree exactly (names + bytes, no extra files). Vaults include:

- **Heavy deduplication**: many files sharing large numbers of identical
  chunks (and whole files identical to other files).
- **Empty files** (multiple), 1-byte files, and files smaller than one chunk.
- **Files exactly `chunk_size` bytes, at 2x `chunk_size`, and one byte over
  or under** a chunk boundary.
- **Deeply nested paths** (4+ directory levels).
- **Binary content** including all 256 byte values, NUL bytes, and 0xFF.

The same program must also handle the visible sample vault correctly.

## Constraints

- No network access at verify time; Python 3 standard library only.
- Do not modify anything under `/app/data` (verification checksums it).
- The verifier runs `/app/restore.py` unchanged on hidden vaults, so do not
  hard-code the sample vault's contents or file names.
