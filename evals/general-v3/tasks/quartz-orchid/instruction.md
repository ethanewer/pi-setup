# quartz-orchid

You are building four small data-integrity tools for an artifact pipeline that must
stay byte-for-byte reproducible. All work happens under `/app`. Leave behind exactly
the deliverables listed below at the exact paths and in the exact formats.

## What is provided in the environment (read them, they are /app files)

* `/app/src/` — a small source tree you must turn into a reproducible tar archive.
  It contains ordinary files, **symlinks** (`bin/alias.txt -> a.txt`,
  `links/guide-link.txt -> ../docs/guide.txt`), one member whose full relative path
  is **longer than 100 characters** (`segments/cache-region-.../mirrored-object-store-...blob`),
  and a **deeply nested** file (`deep/level0/level1/level2/level3/level4/level5/level6/level7/leaf.txt`).
* `/app/tree/` — a nested file tree (regular files, one binary file, one empty file)
  used for the digest task.
* `/app/vault.7z` — a password-encrypted 7z archive. It contains exactly one member,
  `payload_secret.txt`. The password is stored on disk; inspect `/app` to find it.
* `/app/credentials/key.txt` — the recovered credential (the archive password).

## Deliverables (create all six; nothing else is graded)

### 1. `/app/mkarchive.sh` (executable) and 2. `/app/reproduce.tar`

Write an executable script `/app/mkarchive.sh` with this interface:

```
/app/mkarchive.sh [SRC_DIR] [OUT_TAR]
```

* `SRC_DIR` defaults to `/app/src`; `OUT_TAR` defaults to `/app/reproduce.tar`.
* It must read the environment variable `BUILD_EPOCH` (integer seconds since the
  Unix epoch). When `BUILD_EPOCH` is **unset or empty**, fall back to the fixed
  constant `1630454400`.
* It must produce a **GNU-format** (long-name capable) tar archive at `OUT_TAR`
  containing the path of every **regular file** and every **symbolic link** under
  `SRC_DIR` (walked recursively). Member name = path relative to `SRC_DIR`, using
  `/` separators, with **no leading `./`**.
* **Symlinks must be stored as symlinks** (their `linkname` preserved) — never
  dereferenced into their target's contents.
* Long (>100 char) and deeply nested member names must be preserved **verbatim**
  (GNU long-name extension).
* **Every** member's modification time (mtime) must equal the chosen epoch
  (`BUILD_EPOCH` if set, else `1630454400`).
* Members must be sorted by name ascending; owner and group normalized to `0`
  (so the archive is reproducible).

`/app/reproduce.tar` must be produced by running `/app/mkarchive.sh` with **no**
`BUILD_EPOCH` set (i.e. the fallback epoch) against `/app/src`. The verifier will
also re-run your script on a hidden source tree with a different `BUILD_EPOCH`.

### 3. `/app/split.py`

Write a splitter that fragments an oversized source record into chunks each within
a byte cap and records an invertible mapping. Interface (plain Python 3, stdlib only):

```
python3 /app/split.py split INPUT CAP OUT_DIR
python3 /app/split.py join  OUT_DIR OUTPUT
```

* `split`: read `INPUT` as raw bytes. If it does not exist, print
  `split: no such file: <INPUT>` to stderr and exit with a non-zero status. `CAP`
  must be a positive integer (`CAP >= 1`); otherwise print a clear error to stderr
  and exit non-zero without writing anything.
* On success, create `OUT_DIR` and write one chunk per split. Chunk files are named
  `chunk_000000`, `chunk_000001`, ... (zero-padded to width 6, ascending). Every
  chunk is exactly `CAP` bytes **except** the last chunk, which holds
  `min(CAP, remaining)` bytes — so every chunk is at most `CAP` bytes.
* Also write `OUT_DIR/manifest.json` recording the inverse:
  `{"input": <input basename>, "size": <input_size>, "cap": <CAP>, "chunks": <K>, "pad": 6}`
  where `K == ceil(size / CAP)`.
* `join`: read `OUT_DIR/manifest.json`, concatenate `chunk_%06d` for index `0..K-1`
  in order, truncate the concatenation to exactly `size` bytes, and write the result
  to `OUTPUT` (overwrite if present). Reassembling a split archive must reproduce
  the original bytes exactly.

### 4. `/app/extract.txt`

Extract the member `payload_secret.txt` out of the encrypted `/app/vault.7z` using
the recovered password and save that member's exact bytes to `/app/extract.txt`.
Run the actual extraction command (`7z`) — do not fabricate the content. The member
is a small text file; it is the concatenated output of the archive member.

### 5. `/app/digester.py` and 6. `/app/digests.txt`

Write `/app/digester.py` (plain Python 3, stdlib only) with this interface:

```
python3 /app/digester.py [TREE_DIR] [OUTPUT]
```

* `TREE_DIR` defaults to `/app/tree`; `OUTPUT` defaults to stdout. When `OUTPUT` is
  a path, write the result lines to that file instead.
* Recursively walk `TREE_DIR` and process **every regular file**. For each, read its
  raw bytes and compute a digest with **PBKDF2-HMAC-SHA256**:
  `hashlib.pbkdf2_hmac("sha256", file_bytes, bytes.fromhex(SALT), ITER, dklen=32)`
  where `SALT` (a 32-char hex string) and `ITER` are:
  `SALT = "ff4c8e17b3013d38f6a9c71b0d21e44a"`, `ITER = 100000`.
* Emit one line per file:
  `<relpath>\t<hexdigest>`
  where `relpath` is the path relative to `TREE_DIR` using `/` separators (no leading
  `./`), and `hexdigest` is the 64-char lowercase hex of the 32-byte result.
* Lines must be sorted ascending by `relpath`.
* `empty.txt` / empty files are processed too — their line is the PBKDF2 of `b""`.

`/app/digests.txt` must equal the output of running `/app/digester.py` over
`/app/tree` (you may run it with `/app/digests.txt` as the OUTPUT argument).

## Constraints

- Work under `/app` only. Do not modify `/app/src`, `/app/tree`, `/app/vault.7z`,
  or `/app/credentials/key.txt`.
- `split.py` and `digester.py` must use only the Python standard library.
- The verifier re-runs `/app/mkarchive.sh`, `/app/split.py`, and `/app/digester.py`
  on new inputs from `/tests/hidden` — they must be general (parameterized by the
  arguments above), not hard-coded to the visible fixtures.
- Match the exact argument order, file names, separators, and epoch values above.

## What "done" looks like (self-check commands)

```
# tar: symlink preserved, long/deep names present, all mtimes are the fallback epoch
python3 - <<'PY'
import tarfile
t=tarfile.open('/app/reproduce.tar')
names=[m.name for m in t.getmembers()]
assert 'bin/alias.txt' in names and t.getmember('bin/alias.txt').issym()
assert all(m.mtime==1630454400 for m in t.getmembers())
assert any(len(n)>100 for n in names) and any(n.count('/')>=8 for n in names)
print('tar ok')
PY

# split -> join round trip
python3 /app/split.py split /app/src/bin/a.txt 4 /tmp/ch
python3 /app/split.py join /tmp/ch /tmp/back
cmp /app/src/bin/a.txt /tmp/back && echo "split ok"

# extraction (self-check only; use the real password from /app/credentials)
7z x -p$(cat /app/credentials/key.txt) -so /app/vault.7z payload_secret.txt

# digests regenerate over /app/tree and compare
python3 /app/digester.py /app/tree /tmp/d.txt
cmp /tmp/d.txt /app/digests.txt && echo "digests ok"
```
