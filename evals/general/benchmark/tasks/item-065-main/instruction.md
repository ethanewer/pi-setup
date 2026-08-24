# Item-065 (medium) — C4-shard packer / unpacker with a byte-exact round trip

You are building the storage layer for a text-dataset pipeline.  Text corpora
arrive as **plain directory trees** of small files, but the pipeline must move
them around as **compressed C4-style shards** (gzip'd JSON-lines bundles with a
manifest), then restore them on the other side.  The hard requirement is a
**reversible directory invariant**: `unpack(pack(T))` must reproduce `T`
*exactly* — same relative layout, same file bytes, same empty directories —
before you worry about optimising speed or size.

## Files in /app

- `/app/source/` — the corpus tree to ship (read-only input; built at image
  creation by `/app/make_tree.py`; you may inspect it).
- `/app/make_tree.py` — deterministic generator for the corpus tree (used by
  the verifier to rebuild the expected input).
- `/app/c4shards.py` — an **incomplete stub** of a shard tool. It already parses
  the CLI (commands `pack` and `unpack`); `pack`/`unpack` bodies
  `raise NotImplementedError`.  **You implement them.**
- No third-party libraries are needed (stdlib only: `os`, `gzip`, `json`,
  `base64`, `argparse`).

## The tool contract

`/app/c4shards.py` must provide (keep these exact signatures and the CLI):

```python
def pack(root, bundle_out, limit=4096): ...   # CLI: c4shards.py pack ROOT BUNDLE_OUT [--limit N]
def unpack(bundle_in, dest): ...              # CLI: c4shards.py unpack BUNDLE_IN DEST
```

`pack` walks `root`, writes a **bundle directory** at `bundle_out` containing:

- `meta.json` — a JSON manifest describing the bundle (at least the list of
  shard filenames),
- one or more `shard-*.jsonl.gz` — gzip-compressed **JSON Lines** files, where
  every filesystem node is one JSON object per line:
  - a directory → `{"type":"dir","path":"...relative.../maybe/empty/dir"}`,
  - a UTF-8 text file → `{"type":"file","path":..., "text":"..."}`,
  - any other bytes (binary, or text not valid UTF-8) →
    `{"type":"blob","path":..., "base64":"..."}`.

`limit` (default 4096) is the approximate uncompressed byte budget per shard:
large trees must split into **multiple** shards.  Ordering inside/among shards
must be deterministic (e.g. sorted relative paths); the verifier does not
require a specific order, only that unpack restores everything exactly.

`unpack` reads the manifest + shards and rebuilds the tree at `dest`, creating
**all** recorded files **and directories** (including empty ones) with the
exact bytes.  Treat files and folders uniformly: a `dir` record is just as
important as a file record.

## Steps

1. **Set the invariants before coding.**  List what must be identical between
   the original tree and a round-trip result: every relative path, every file's
   byte content, every empty directory.
2. **Implement `pack` and `unpack`** in `/app/c4shards.py` per the contract.
   Use `/app/make_tree.py` logic as your test corpus (already in `/app/source`).
3. **Round-trip test before optimising**: build a bundle from `/app/source`,
   unpack it to a fresh directory, and diff the two trees
   (`diff -r` or a small Python walker).  Iterate until byte-exact.
4. Produce the deliverables below, and (optionally) also exercise
   `--limit 64` to force multiple shards and prove sharding determinism.

## Deliverables (checked by the verifier)

- `/app/c4shards.py` — implemented (no unresolved `NotImplementedError`).
- `/app/bundle_shards/` — the packed bundle produced by your `pack` from
  `/app/source`.  It must contain a `meta.json` and **at least two**
  `shard-*.jsonl.gz` files (the corpus is small, so choose a small `--limit`,
  e.g. `--limit 256`, to force several shards).
- Optionally `/app/restored/` — your own unpack result (not required; the
  verifier performs its own unpack).

The verifier rebuilds the expected tree with `make_tree.py`, runs *your* CLI
(`pack` then `unpack`) and also unpacks **your** `/app/bundle_shards/`, then
compares trees byte-for-byte.  Full success requires: CLI works, multiple
gzip shards exist, and both round trips are exactly equal to the expected tree.