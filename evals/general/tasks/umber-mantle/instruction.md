# umber-mantle — archive-and-binary packaging

You are given an input tree rooted at `/app`. Produce three artifacts plus a
reusable solver, following the exact contract below. The verifier checks each
artifact, then re-runs your solver on fresh hidden input trees, so the solver
must be generic (no hard-coded filenames, content or paths from this /app).

## Input tree

```
/app/
  data/                              <- source dataset directory
    records/main.csv               (dataset file — MUST remain byte-identical)
    records/other.csv
    aux/index.txt
    scripts/etl_probe.py           (example fixture — MUST remain byte-identical)
    scripts/seed.py
    scripts/__pycache__/etl_probe.cpython-312.pyc     (cache — do not ship)
    third_party/kittor/lib/kit.py                     (vendored dep — do not ship)
    third_party/kittor/METADATA
    local/build/syms.o                               (build object — do not ship)
    version.manifest                                 (version metadata — do not ship)
    credentials.file              (mode 0600 — restricted perms — do not ship)
    box.txt
  place/
    feed-0.printer              (a compressed printer-file whose top-level path differs between trees)
  payloads/
    raw.log                     (a large interacting live log — MUST remain untouched)
    archive.tar.gz              (members: readme.txt, map.hex, big.bin, raw.log[SENSITIVE])
```

## Deliverables

### 1. `/app/out.tar.gz` — exclude-aware compressed archive
Create a **gzip-compressed tar** of the **contents of `data/`** such that:
- Entries keep the **leading `data/` path component** (e.g. extraction restores
  `data/records/main.csv`). Archiving "from inside" `data/` so the `data/`
  component is lost is a failure.
- **Exclude** the following members entirely:
  - any path containing a `__pycache__` directory (caches, incl. `*.pyc`)
  - any path containing a `third_party` or `local` directory (vendored deps,
    build objects; includes `local/build/*.o`)
  - any file named `version.manifest` (version metadata)
  - any `*.o` / `*.pyc` file (object artifacts / caches)
  - any file that is **not world-readable** (mode bit for "others" read missing),
    such as `credentials.file` (0600)
- the archived copy of any included file is **byte-identical** to its source.

### 2. `/app/decoded.raw` — decompressed printer file
`place/*.printer` holds the *compressed* printer-file unless already plaintext.
Write **`/app/decoded.raw`** = the **uncompressed** contents of that printer-file.
If the file's first two bytes are `1f 8b`, deflate it (gzip); otherwise copy it
verbatim. The output must be exactly the decoded text.

### 3. `/app/out.bin` — reassembled binary artifact
`payloads/archive.tar.gz` contains several members. Stream **only** the
`map.hex` member's bytes out of the archive (do **not** extract the whole
archive to disk — the archive shares its directory with the large live `raw.log`
and full extraction clobbers it).

`map.hex` is an `xxd`-style hex dump: each line begins with an 8-digit byte-offset
column, then 16 two-digit hex byte-groups separated by single spaces, then a
two-space gap and an ASCII annotation column you may ignore. Reassemble the
bytes by collecting the **two-digit hex groups** in line/first-order (ignore the
offset and annotation columns) — the result is a small ELF binary. Write the
exact byte sequence to **`/app/out.bin`** (do not append anything).

## Reusable solver: `/app/build.sh`
Leave an executable **`/app/build.sh`** whose only argument is a base directory
(default `/app`) and which, given any such tree (with the same `data/`, `place/`,
`payloads/` layout), produces the three deliverables **inside that base
directory**:
- `$BASE/out.tar.gz`, `$BASE/decoded.raw`, `$BASE/out.bin`.
It must not read `/tests`, `/solution`, or any hidden files, and must not modify
any of the *input* files (including `payloads/raw.log`). Run it once on `/app`
so the three deliverable files exist under `/app`.

## Constraints / edge cases
- Do **not** modify `data/records/main.csv`, `data/scripts/etl_probe.py`, or
  `payloads/raw.log`. The verifier hashes them and requires exact originals.
- Handle a printer file that may already be plaintext (no `1f 8b` header).
- Handle trees where the `__pycache__` directory is absent, and where the
  printer filename varies — the solver must glob `place/*.printer` and require
  exactly one.
- Handle a hex dump whose last line is partial (fewer than 16 bytes).
- The archive must be gzip-compressed (starts with the bytes `1f 8b`).

## Final state required
```
/app/build.sh          (executable, reusable)
/app/out.tar.gz
/app/decoded.raw
/app/out.bin
```
No other files in `/app` are required. Do not modify anything under `/tests` or
`/logs`.