# Manage a file tree: zero-byte leaves, entry-capped repack, LF-only text

This task has three independent parts. You must write three small, reusable
Python CLIs and run each one on the shipped input to produce visible output
trees. All three tools must behave on **any** input following the documented
contract, not just the supplied files — the verifier re-runs each tool on fresh
hidden inputs and checks the results and error handling.

## Deliverables (all under `/app`)

- `/app/mk_leafs.py` — instantiate a tree of **zero-byte files** from a listing.
- `/app/reshard.py` — repack a tree so every directory holds at most a fixed
  item count and no file exceeds a fixed byte budget.
- `/app/normalize_newlines.py` — normalize text files to LF-only line endings
  while leaving binary members byte-identical.
- `/app/output_tree` — the tree produced by running `reshard.py` on
  `/app/input_tree` (see the commands below).

Do **not** modify any input file shipped under `/app` (`/app/listing.txt`,
`/app/input_tree/...`, `/app/mixed_tree/...` are read-only data). Do not read
`/tests` or `/solution`. Python 3 is available (`python3`); only the standard
library is needed. No network during verification.

## Tool 1 — `/app/mk_leafs.py`

Create the directory structure of a listing while keeping every file empty.

```
python3 /app/mk_leafs.py --listing <listing.txt> --outdir <dir>
```

Listing format (all relative, no absolute paths):

- One entry per line. Lines that are empty or contain only whitespace are
  ignored. A line whose first non-space character is `#` is a comment line and
  is ignored.
- Leading/trailing whitespace on a line is trimmed.
- A line ending in `/` is a **directory** entry: create that directory
  (including parents). It ends up empty.
- Any other non-ignored line is a **file** entry: create a **zero-byte regular
  file** at that path, creating parent directories as needed.
- Entries repeat safely (idempotent).

Errors (reject the whole run): print a clear message to stderr and exit
**non-zero** when a trimmed entry is an absolute path (`/...`), or contains a
`..` component (leading `..` or `..`/... anywhere), or when creating a file
entry whose parent already exists as a regular file (or vice-versa: a directory
entry whose parent is a file). On success exit `0`.

Outcome the verifier checks: for every file line, an existing **zero-byte**
file at `<outdir>/<path>`; for every directory line, an existing directory.

## 2 — `/app/reshard.py`

Repackage a source directory tree into an output directory that obeys two caps:

```
python3 /app/reshard.py --input <dir> --output <dir> --max-items N --max-bytes B
```

- `N` (>=1) = the maximum number of **items** any directory may hold.
- `B` (>=1) = the maximum **bytes** any single file may hold.

Behavior:

1. Walk `--input` recursively, ignoring non-regular files. Process the regular
   files in **ascending** order of their input-relative path (a plain `sorted`
   on the relpath strings).
2. For each file of `size` bytes:
   - `pieces = 1` when `size <= B`, else `ceil(size / B)`.
   - A `pieces == 1` file is kept whole; a `pieces > 1` file is split into that
     many consecutive parts, each of which has size `<= B` (all parts together
     byte-equal the original, in order).
3. The parts are written into **shard** subdirectories of `--output` named
   `shard-000`, `shard-001`, ...
   - Each shard directory holds **at most `max-items` ** items (each part is one
     item).
   - All parts of one file live in the **same** shard directory and appear
     there in split order. All inputs supplied to the tools guarantee a single
     file never needs more pieces than `N`; the cap therefore always fits.
4. Part file names: let `k` be the source file index among all files, starting
   at 0, in the ascending input order above. A single-part file is written as
   `<out>/<shard>/f_<k six-digits>` and a split file as
   `<out>/<shard>/f_<k>_<p>` for part `p` in `0..pieces-1`. These names are
   globally unique, so no shard collision occurs; you must keep them sorted as
   described so reassembly order is deterministic.
5. `--output` is created (or emptied) and, alongside the shard directories, a
   manifest is written to `<output>/manifest.tsv` — one line per source file
   with **tab**-separated columns:
   ```
   <relpath>   <comma-joined out-list of the output part paths, relative to OUTPUT>   <0|1>
   ```
   where the third column is `1` when the source file was split and `0` when it
   was kept whole. Out part paths are relative to `--output` (e.g.
   `shard-002/f_000003_1`), joined with commas in split order. The manifest is
   written in the same ascending input order. Rows must precede exactly as the
   file order above; no header row.

Guarantees the verifier relies on, and which the contract guarantees: no output
file under `--output` exceeds `B` bytes, every directory (including `--output`
itself) holds at most `N` items, every source regular file is reassemblable by
concatenating its listed parts in order to bytes identical to the source file.
Fail loudly (non-zero exit, message on stderr) if `--input` is not a directory,
or `N<1`, `B<1`, or a file whose piece count would exceed `N` (which the
supplied inputs avoid).

On success exit `0`.

## 3 — `/app/normalize_newlines.py`

```
python3 /app/normalize_newlines.py --src <dir> --dst <dir>
```

- Walk `--src` recursively and rebuild the same structure under `--dst` (create
  missing parent directories). Only regular files are materialized.
- Determine, for each file, text vs binary: a file is **binary** if any NUL
  byte (`0x00`) occurs in the first 4096 bytes (or the whole file if shorter);
  otherwise it is **text**.
- Text file: replace every line ending with a single `\n` (LF). Concretely
  normalize bytes as `data.replace(b'\r\n', b'\n').replace(b'\r', b'\n')` and
  write the result. A correctly-normalized text file contains no `0x0D` byte at
  all.
- Binary file: byte-for-byte identical copy (content must be byte-same between
  `--src` and `--dst`).

Exit `0` on success; non-zero with stderr message on any read/write failure.

## Commands you are expected to run

```
python3 /app/mk_leafs.py --listing /app/listing.txt --outdir /app/leaf_tree
python3 /app/reshard.py --input /app/input_tree --output /app/output_tree --max-items 6 --max-bytes 4096
python3 /app/normalize_newlines.py --src /app/mixed_tree --dst /app/clean_tree
```

`/app/input_tree/b/big.txt` (9600 bytes) is larger than the 4096-byte budget,
so it is split in `output_tree`; all other `/app/input_tree` files fit whole.

## Verification / hidden edge cases

The verifier re-runs all three tools against fresh inputs under `/tests/hidden`
with the same contracts, and also checks error handling. Make your tools handle:

- **leafs**: deep nesting, files/dirs whose names contain spaces, comment and
  blank lines, trailing-slash directory entries, a path whose parent collides
  with a file, absolute and `..` entries that must be rejected (non-zero, and
  nothing meaningful written to outdir), empty listing (outdir may be empty,
  exit 0).
- **reshard**: many small files with a small `N` (multi-shard output), a file
  larger than `B` (multiple parts), an empty source tree (output holds only a
  manifest with zero shard rows, exit 0), and `N`/`B` as small positive ints.
- **normalize**: text with CRLF/lone-CR (→ LF-only), already-LF text (unchanged
  content), a NUL-containing binary under 4096 bytes, and a NUL-containing
  binary larger than the boundary.