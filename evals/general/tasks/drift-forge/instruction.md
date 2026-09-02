# drift-forge — Ridgeline freight-tree drift-sync pipeline

## Scenario

**Ridgeline** is a small logistics platform that keeps an on-prem mirror of a
distant warehouse's "freight tree". Files arrive in inconsistent shapes, and the
platform runs four small `python3` tools to normalise, repackage, fingerprint and
decode them before they go into the ledger. Your job is to author those four
tools at fixed paths under `/app`, and to run them on the fixtures shipped in the
image so they leave the required artifacts behind.

Everything is deterministic, pure `sys`/`os`/`struct`/`hashlib`/`json`, no third
party imports, no network. Use whatever small helper files you like in `/app`,
but nothing you write may ever read from or write into `/tests`.

---

## Deliverables

| Path | What it is |
|------|-----------|
| `/app/normalize_lf.py` | tool 1 — normalise text line endings, leave binaries byte-identical |
| `/app/reshard.py` | tool 2 — repackage a tree under item + byte caps |
| `/app/output_tree` | produced by running `python3 /app/reshard.py /app/input_tree /app/output_tree 4 2048` |
| `/app/order_and_hash.py` | tool 3 — deterministic manifest + reproducible archive |
| `/app/manifest.json` | produced by `order_and_hash.py manifest` on `/app/seed_tree` |
| `/app/parse_fw.py` | tool 4 — fixed-width ledger record parser |

All four scripts must be executable and invokeable as `python3 /app/<name>`.

Run tool 2 on the shipped `input_tree` fixture with `max_items=4, max_bytes=2048`
to produce `/app/output_tree` (do not use any other caps), and run tool 3's
`manifest` subcommand on the shipped `seed_tree` fixture to produce
`/app/manifest.json`. Those two artifacts are deliverables the graders inspect.

---

## Tool 1 — `/app/normalize_lf.py`

Usage:

```
python3 /app/normalize_lf.py <in_dir> <out_dir>
```

- Recursively visits every regular file under `<in_dir>`, preserving the
  relative directory structure into `<out_dir>`.
- A file is **binary** iff its full byte content contains at least one NUL byte
  (`0x00`). Every other file is **text**.
- **Text** files are rewritten so that *every* line break is exactly one `LF`
  (`0x0A`): replace each `CRLF` (`0x0D 0x0A`) with `LF`, then each remaining
  lone `CR` (`0x0D`) with `LF`. All non-newline bytes are passed through exactly.
- **Binary** files are copied so their bytes are **byte-identical** to the
  source, *even if they happen to contain CR/LF bytes* (they contain a NUL, so
  they are binary and must not be altered).
- Output rules: if `<out_dir>` exists it is removed and recreated fresh (so no
  stale files survive). Non-regular files (symlinks, sockets, FIFOs) are skipped.
- Exit code `2` and a usage message when arguments are wrong or `<out_dir>` is
  inside `<in_dir>`; otherwise exit `0`.

Edge cases the graders probe (and you must handle): a text file whose only
newlines are `CRLF`, a text file with lone `CR` endings (old-Mac), mixed
endings, a `CR`/`CRLF` at the very end of the file, a `0`-byte file, text with
Unicode, and binary containers that themselves contain CR/LF sequences (they
must come out bit-for-bit unchanged).

---

## Tool 2 — `/app/reshard.py`

Usage:

```
python3 /app/reshard.py <in_dir> <out_dir> <max_items> <max_bytes>
```

Repackage all regular files under `<in_dir>` into `<out_dir>` so that **both**
caps hold:

- **Item cap** `max_items`: every directory in the output tree (including the
  output root) directly holds **at most `max_items` regular child files**.
  Subdirectories themselves are not counted; only direct child *files* of that
  directory count toward its cap.
- **Byte cap** `max_bytes`: every regular file in the output tree is `<=
max_bytes` bytes. Files larger than `max_bytes` must be split into consecutive
chunks each `<= max_bytes`.
- **Preservation**: every byte of every input file appears exactly once in the
  output tree (nothing lost, nothing duplicated).

The output is a set of flat **shard** directories named
`shard_<N>` (N = the first global item index placed into it, zero-padded to four
digits). Items are laid out this way:

- Gather the input's regular-file relative paths, sort them (stable, byte
  order), and read each file's bytes.
- For a file of length `L <= max_bytes` this yields a **single item**: one
  output file whose bytes are exactly the input bytes.
- For a file of length `L > max_bytes`, split into chunks
  `data[0:max_bytes], data[max_bytes:2*max_bytes], …`; every chunk becomes an
  item. Each chunk's output name is the base name plus `.part_<i>` where `<i>`
  is the zero-based chunk index, zero-padded to three digits (or more if needed,
  e.g. `.part_000`, `.part_001`, …). Concatenating a file's chunks in index
  order must reproduce the original bytes.
- Item output names are made collision-free across the tree by replacing every
  `/` in a file's relative path with `__` (two underscores) — so a file
  `a/b.txt` and a file `a_b.txt` can never collide.
- Fill sharder N with (at most `max_items`) items before opening sharder N+1.
  The sharder directories are the only children of the output root (the output
  root itself holds no files directly).

So, to be concrete, if the whole input is 3 files and `max_items=2`, you must
end up with `out/shard_0000` (2 items) and `out/shard_0004` (1 item).

Exit code `0` on success; print a usage line and exit `2` on bad arguments or if
`max_bytes <= 0`.

---

## Tool 3 — `/app/order_and_hash.py`

Two subcommands, both deterministic and locale-independent:

```
python3 /app/order_and_hash.py manifest <in_dir> <out_json>
python3 /app/order_and_hash.py bundle <in_dir> <out_archive>
```

- First list all regular-file **relative paths** under `<in_dir>` and sort them
  straight on their UTF-8 byte sequence (equivalently Python's plain codepoint
  string sort); never use locale-aware collation and never bake in owner/group,
  user, timestamp, or host fields anywhere.

`manifest` writes `<out_json>`:
```json
{
  "entries": [
    {"path": "…", "size": <int bytes>, "sha256": "<64 hex chars>"},
    …
  ]
}
```
one entry per file (in the sorted order), `sha256` of the raw file bytes. The
JSON must be byte-dead the same from a fresh run.

`bundle` writes `<out_archive>` — a custom reproducible archive:
- first 16 bytes, the magic `b"DRIFT-FM-01\n"`;
- then, for each file in sorted order:
  - a 4-byte big-endian unsigned length of the UTF-8 encoded relative path,
  - the path bytes,
  - an 8-byte big-endian unsigned file size,
  - the raw file bytes.

Running it twice on the same input must yield byte-identical archives; running
it on two identically-populated directories must also yield byte-identical
archives (no timestamps, no owners, no incidental ordering).

---

## Tool 4 — `/app/parse_fw.py`

Usage:

```
python3 /app/parse_fw.py <in.records> <out.json>
```

The input is a plain sequence of 40-byte records guiphonated with no separators
and no trailing newline. A record is classified by `bytes[0:2]`, and every
numeric field is **right-aligned, zero-padded** (leading zeros, no padding
spaces).

Layouts:

| tag | record | offsets |
|-----|--------|---------|
| `AC` | account | `[0:2]` tag; `[2:10]` code (8, left, space-padded); `[10:24]` holder (14, space-padded); `[24:40]` balance — 16 bytes right-aligned zero-padded decimal integer |
| `BO` | book | `[0:2]` tag; `[2:10]` code (8); `[10:26]` title (16); `[26:40]` pages — 14 bytes right-aligned zero-padded decimal integer |
| `TX` | transaction | `[0:2]` tag; `[2:10]` txn id (8); `[10:18]` account code (8); `[18:26]` kind (8); `[26:39]` amount — 13 bytes right-aligned zero-padded decimal integer; `[39:40]` sign — one byte, `+` or `-` |

Text fields are `strip()`ped of spaces. Numeric fields are `.strip()`-ed then
parsed with `int(...)`. Output `<out.json>`:

```json
{
  "records": [
    {"type": "AC", "code": "…", "holder": "…", "balance": <int>},
    {"type": "BO", "code": "…", "title": "…", "pages": <int>},
    {"type": "TX", "txn": "…", "account": "…", "kind": "…", "amount": <int>, "sign": "+"}
  ],
  "summary": {
    "n_account": <int>, "n_book": <int>, "n_txn": <int>,
    "n_unknown": <int>, "n_malformed": <int>,
    "total_balance": <int>, "total_pages": <int>, "net_amount": <int>
  }
}
```

- Records appear in file order.
- `total_balance` = sum of every `AC.balance`.
- `total_pages` = sum of every `BO.pages`.
- `net_amount` = sum of signed `TX` amounts: add `amount` when `sign=="+"`,
  subtract when `sign=="-"`.
- A 40-byte block whose two-byte tag is not `AC`/`BO`/`TX` is emitted as
  `{"type": "unknown", "offset": <int>}` and increments `n_unknown`.
- If the input length is **not** a multiple of 40, the leftover trailing
  block (< 40 bytes) is emitted as `{"type": "malformed", "offset": <int>}`
  and increments `n_malformed`.
- An empty file (0 records) is valid: `records: []`, all counts and totals
  `0`.

Getting a single numeric field boundary off by one corrupts every later record
in the file — that is the exact failure mode this tool must avoid.

---

## Fit / constraints

- Everything runs as a plain Python 3.12 process; `findutils`, `python3`, `file`
  are present in the image. Do `apt-get`/`pip` installs if you wish but nothing
  is required beyond the standard library.
- Do not read or write anything under `/tests`. Do not depend on absolute host
  paths other than `/app/...`.
- All four tools must be re-runnable from a fresh container against brand-new
  inputs with no further state; do not hard-code our fixture contents into any
  tool.