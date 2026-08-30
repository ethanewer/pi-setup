# Release-archive triage (kite-helix)

You are the release engineer for a cargo-shipping ledger service. A messy
archive-and-filesystem workspace must be triaged into a clean, verifiable release
bundle. Write **one self-contained Python program** at **`/app/solve.py`** that does
all of the work, and run it to produce `/app/out/` and `/app/answer.json`.

The program must be **reusable on any workspace directory**: it takes the workspace path
as its single command-line argument and must work for that directory no matter what its
specific file contents, names, or tokens are. The verifier will run it on several
differently-named workspaces. Do **not** hard-code any specific file contents or tokens.

## 1. Layout contract

`solve.py <workdir>` receives a directory containing a `data/` subdirectory:

```
<workdir>/data/
  manifest/artifact.zip   # a zip archive whose table of contents matters
  pkg/                    # a source tree to be packaged into release.zip
  deep/                   # a deep, long-named tree containing one symlink
  mirror_src/             # gzip-compressed payload files (*.dat.gz)
  hash/                   # a nested tree of files to hash
```

You read `<workdir>/data/...` and you write:
- `<workdir>/out/` (the outputs specified below), and
- `<workdir>/answer.json`.

Do **not** modify anything under `<workdir>/data/`. It must remain byte-for-byte
identical after your program runs (the verifier fingerprints every source file before
and after the run, and fails the whole task if any source byte changed).

## 2. Step 1 — surface the wanted archive member

`data/manifest/artifact.zip` holds a `config.yaml` member at several different logical
paths (a `release` one, a `staging` one, a `backup` one, an `expr` variant, ...).
Exactly **one** member has the full path

```
manifest/release/current/config.yaml
```

The other near-identical members deliberately carry different `app_token` values.
List the archive's table of contents, locate that exact member, and read it. Extract
its `app_token` field, which appears on a line like:

```
app_token: rlz-abcd-1234
```

The value may be unquoted or single-/double-quoted with optional surrounding
whitespace; parse it robustly. Store the value in `answer.json` under the key
**`"token"`**. Grabbing the wrong member yields a wrong token.

## 3. Step 2 — package `pkg/` excluding path patterns

Create the zip archive **`<workdir>/out/release.zip`** from `data/pkg/`, recursively.
Include every regular file except entries matching **any** of these exclusion rules:

1. any path component named exactly `vendor` or `__pycache__`;
2. a file whose name ends with one of `.pyc`, `.o`, `.tmp`, `.cache`;
3. a file not readable by its owner (permission bits `000` — restricted-permission).

Precision matters: `vendor.py` ends with `.py` (not `.pyc`/`.o`), `compile.tmp.txt`
ends with `.txt` — they are **not** excluded. Only directory components named exactly
`vendor` / `__pycache__` and the exact filename suffixes above are dropped. Keep every
other file. Store each included file by its path relative to `pkg/` (use `/`
separators). Include file entries only (no directory entries). The member set of the
resulting zip must exactly match the expected set computed from the rules above.

## 4. Step 3 — bundle the deep tree preserving symlinks and long names

Create the gzip-compressed tar **`<workdir>/out/deep.tar.gz`** whose content is the
`data/deep/` tree rooted at the entry named `deep`.

Requirements:
- The tree contains one **symlink** (its target is a relative path). Store it as a
  symlink — do **not** dereference it into its target's content. Its link target must
  remain the exact relative path found on disk.
- The tree also contains deeply nested directories and **file names longer than 100
  characters**. Use a tar format that stores such long/deep members losslessly (e.g.
  the GNU/PAX format). No member name may be truncated.

The verifier opens the tar and confirms: the symlink member is stored as type symlink,
its relative link target resolves to another member that is present **inside** the
archive, and at least one member name is longer than 100 characters and intact.

## 5. Step 4 — mirror the source tree into `out/mirror/`

`data/mirror_src/` holds one or more gzipped payloads named `*.dat.gz` (possibly in
nested subdirectories). Create **`<workdir>/out/mirror/`**. For every `*.dat.gz` under
`mirror_src/`, write its **decompressed** byte content to `out/mirror/` under the file
named with the `.gz` removed (so `foo.dat.gz` becomes `out/mirror/foo.dat`). Each
output file is named by its original basename and sits directly at the top of
`out/mirror/`. The verifier compares every decompressed file byte-for-byte.

## 6. Step 5 — hash every file in the nested hash tree

`data/hash/` is a nested tree of files. Compute the **SHA-256** hex digest of every
regular file in it. Put under `answer.json` key **`"hash"`** a JSON object whose keys
are each file's path **relative to `data/hash/`** (use `/` separators; file names may
contain spaces and binary bytes) and whose values are the lowercase hex SHA-256 digest
strings. The map must cover every file that exists (nothing missing, nothing extra).

## 7. `answer.json` format

```json
{
  "token": "<string>",
  "hash": { "<relative path>": "<lowercase hex sha256>", ... },
  ...you may add any other keys...
}
```

Only `token` and `hash` are verified (exact match); extra keys are ignored.

## 8. Deliverables and final state

Create and make executable `/app/solve.py`, then run it once on the workspace:

```bash
chmod +x /app/solve.py
python3 /app/solve.py /app
```

leaving you with `/app/answer.json` and `/app/out/{release.zip, deep.tar.gz,
mirror/}`. This must succeed on first invocation. Remove any test scaffolding, and do
not leave `data/` modified.

## Edge cases the workspace may throw at you

- Near-duplicate archive paths and decoy tokens — read the member listing.
- File names containing spaces.
- Multiple `*.dat.gz` files, possibly nested in directories.
- Binary bytes inside `data/hash/` files — hash the raw bytes.
- A non-readable (mode `000`) file inside `pkg/` that must be skipped, not read.
- Very long / deeply nested member names inside `data/deep/` — do not truncate.