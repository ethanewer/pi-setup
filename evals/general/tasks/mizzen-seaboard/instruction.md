# mizzen-seaboard

You are working inside a real open-source codebase: **psycopg** (the
PostgreSQL adapter for Python, `psycopg/psycopg`), checked out at a pinned
historical commit in `/app/src` (detached HEAD, working tree clean). There is
a bug in this tree's handling of the `client_encoding` connection option.
Your job is to find it, fix it in the working tree, and prove the fix with
the project's own test tooling. You are deliberately **not** told which file
or function to change: localising the bug is part of the task.

## Environment

- The source tree is at `/app/src` and is writable by you, but **do not
  commit, fetch, push, rebase or otherwise modify `.git`** — the working tree
  is detached at the pinned commit and must stay there. No network exists in
  this container; everything needed is baked in.
- Python 3.12 and `pytest` (9.1.1) are installed. The `psycopg` package is
  also installed as a non-editable copy in site-packages; after editing the
  tree you can either run checks with the tree's package dir forced onto
  `sys.path` (the mechanism used by `/app/repro.sh` below) or refresh the
  site-packages copy yourself with `cp -a` (see `/app/README-BUILD.md`).
  Never use `pip install` against the tree — no network, so pip's build
  isolation would fail.
- `cpus = 1`: one vCPU. The tree is pure Python; tests and installs run in
  seconds.
- `/opt/prefix/psycopg` is a **pristine, read-only** copy of the `psycopg`
  package exactly as it was at the pinned commit (baked into the image at
  build time). The default setting of `/app/repro.sh` uses it.
- The project's own test suite lives under `/app/src/tests/`. This task's
  behaviour is tested by `test_encodings.py`; the related DB-free files
  `test_conninfo.py` and `test_sql.py` also run without a PostgreSQL server.

## The bug (user-visible symptom)

PostgreSQL documents a charset table: every server encoding has one
canonical name and, for many encodings, a set of **official alias names**.
A user may pass any of these names as the value of the `client_encoding`
option in a connection string, e.g. (truncated for brevity)
`dbname=db1 user=alice client_encoding=MSKANJI`. The documented contract is
that a connection string's `client_encoding` names the encoding PostgreSQL
should use to send text to the client: both the canonical names and all of
the documented alias names must resolve to the matching text codec.

On this tree, many of the documented **alias names** are silently ignored:
psycopg does not recognise them and quietly falls back to UTF-8 instead of
using the requested encoding. The server then sends text in the requested
encoding but the client decodes it as UTF-8, so the text comes out garbled —
no exception is raised, no warning is printed, nothing. For example, a user
who sets `client_encoding=MSKANJI` (the documented PostgreSQL name for the
Shift_JIS / SJIS encoding) gets UTF-8 decoding with corrupted Japanese text
instead of `shift_jis` decoding. The same happens for aliases such as the
`WIN9xx` / `Windows9xx` names, `Big5`'s alias set, `Unicode` for UTF8, and
so on. The canonical names themselves work correctly.

The PostgreSQL documented charset table (canonical name followed by its
official aliases) is:

```
BIG5                WIN950, Windows950
EUC_CN
EUC_JIS_2004
EUC_JP
EUC_KR
EUC_TW
GB18030
GBK                 WIN936, Windows936
ISO_8859_5
ISO_8859_6
ISO_8859_7
ISO_8859_8
JOHAB
KOI8R               KOI8
KOI8U
LATIN1              ISO88591
LATIN2              ISO88592
LATIN3              ISO88593
LATIN4              ISO88594
LATIN5              ISO88599
LATIN6              ISO885910
LATIN7              ISO885913
LATIN8              ISO885914
LATIN9              ISO885915
LATIN10             ISO885916
MULE_INTERNAL
SJIS                Mskanji, ShiftJIS, WIN932, Windows932
SHIFT_JIS_2004
SQL_ASCII
UHC                 WIN949, Windows949
UTF8                Unicode
WIN1250
WIN1251             WIN
WIN1252
WIN1253
WIN1254
WIN1255
WIN1256
WIN1257
WIN1258             ABC, TCVN, TCVN5712, VSCII
WIN866              ALT
WIN874
```

Every name in this table should be accepted as the `client_encoding` value
in a connection string and resolve to the same Python codec that the
canonical name of its row resolves to (`SJIS`/`MSKANJI`/`WIN932` →
`shift_jis`, `UTF8`/`Unicode` → `utf-8`, `UHC` → `cp949`, `WIN866`/`ALT` →
`cp866`, ...). The task is to make psycopg do that.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom described above. Its contract:

   - It is an executable bash script (`#!/usr/bin/env bash`, run it with
     `chmod +x`), runnable from **any** current working directory.
   - It honours the environment variable `PSYCOPG_PACKAGE_DIR`: the
     directory to import the `psycopg` package from. When unset it defaults
     to `/opt/prefix/psycopg` — the pristine, unmodified copy of the package
     baked into the image. The script itself handles the import plumbing
     (putting that directory at the front of `sys.path` / `PYTHONPATH` —
     e.g. `sys.path.insert(0, "$PSYCOPG_PACKAGE_DIR")` in a `python3 -`
     heredoc) and must not depend on the cwd at all.
   - It uses (only) a scratch directory of its own under `/tmp` and never
     writes anything under `/app/src` or `/opt`.
   - It checks that every one of the following documented alias names
     resolves, through psycopg's own connection-string handling, to the
     Python codec of its row's canonical charset: `MSKANJI` (→ `shift_jis`)
     plus **at least two other alias names** from the table above (pick any,
     e.g. `WIN932`, `ShiftJIS`, `Unicode`, `WIN949`, `KOI8`, `ALT`,
     `ISO88591`). It additionally checks that at least one canonical name
     (e.g. `EUC_JP` → `euc_jp`) still resolves, and that at least one
     unknown name (e.g. `WAT`) still falls back to `utf-8`.
   - It prints every check it performs and its outcome to stdout, and
     nothing else.
   - It exits `0` if and only if every check holds, and non-zero otherwise.

   On the **unfixed** tree this script must fail: with the default
   `PSYCOPG_PACKAGE_DIR`, the alias checks resolve to `utf-8` instead of the
   correct codecs. Confirm that now, before fixing anything — this proves
   the symptom is real in this exact environment.

2. **Fix the tree.** Make the smallest possible change so that `/app/repro.sh`
   passes with `PSYCOPG_PACKAGE_DIR=/app/src/psycopg` — i.e. every documented
   alias name resolves to the right codec while canonical names, unknown
   names, and everything else keep behaving exactly as before. Fix the
   mechanism, not just one input: the same defect is reachable through every
   alias in the table, through casing variants (lookups are case-insensitive
   and ignore `-`/`_` noise characters), and through the codec-resolution
   entry point itself (see Grading). Do not merely special-case a handful of
   strings in a wrapper script — the graded checks exercise the real code
   path.

3. **Break nothing else.** Everything else must keep working exactly as
   before: canonical encoding names, unsupported/unknown names (which must
   still silently fall back to `utf-8`), and the project's own test files.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file (and do not leave new files like
   `.pytest_cache` or `__pycache__` in the tree); make no commits; do not
   modify `tests/`, `pyproject.toml` or any other file. The grader compares
   every file's bytes against the pinned commit's own blobs, so cosmetic
   side-changes also fail. Your two authored files `/app/repro.sh` and
   `/app/summary.md` live **outside** `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce**: from any directory, `bash /app/repro.sh` (defaults to the
   pristine copy) — observe that the alias checks fail while the canonical /
   fallback checks pass. Try a couple of alias spellings directly through
   psycopg's conninfo handling to pin down precisely which inputs break.
2. **Localise** the bug by reading the code: trace where a
   `client_encoding` value from a connection string is resolved to a Python
   codec name, and what the existing mapping table looks like ('noise'
   characters and case are normalised on lookup). Understand *why* the
   canonical names hit the table but the documented aliases do not before
   you patch. `tests/test_encodings.py` shows exactly how this public-facing
   piece is exercised by the project itself, and every codec name psycopg
   already uses for each canonical charset appears in the mapping.
3. **Fix** with the smallest possible change in that one source file, then
   confirm:
   - `bash /app/repro.sh` still **fails** (pristine default), and
   - `PSYCOPG_PACKAGE_DIR=/app/src/psycopg bash /app/repro.sh` now
     **passes**.
4. **Prove nothing else broke**: run the project's own test files from
   `/app/src` after refreshing the site-packages copy from your tree
   (`rm -rf /usr/local/lib/python3.12/site-packages/psycopg && cp -a
   /app/src/psycopg/psycopg /usr/local/lib/python3.12/site-packages/psycopg`):
   `python3 -m pytest tests/test_encodings.py tests/test_conninfo.py
   tests/test_sql.py -q -o cache_dir=/tmp/pytestcache` — all must stay green
   (`test_sql.py` normally skips 80 server-dependent tests; that is fine).
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream
  fix commit is **not** reachable from this clone, and that every tracked
  file except the single source file the bug lives in is byte-identical to
  that commit (any other modification, added file or stray untracked file
  fails);
- require `/app/repro.sh` and `/app/summary.md` to exist, be non-empty and
  behave per their contracts;
- run your `/app/repro.sh` against the repaired tree (it must pass with
  `PSYCOPG_PACKAGE_DIR=/app/src/psycopg`) **and** against the pristine
  pre-fix package at `/opt/prefix/psycopg` (it must fail — proving the
  symptom is real and your reproduction targets it);
- refresh the installed library from your tree and verify the installed
  package itself resolves the aliases correctly (the graded checks import
  the library, not a stub);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` at build time, sha256-pinned — upstream added it
  with the fix, so it does not exist in this tree) over
  `tests/test_encodings.py` and run the whole file: all 21 tests must pass,
  including both discriminating `MSKANJI`/`mskanji` rows;
- run the previously-existing DB-free project test files
  `tests/test_conninfo.py` (43 tests) and `tests/test_sql.py` (44 passing,
  80 server-dependent skips) and require them to stay green;
- run **hidden cases I authored** (two pytest files) that exercise the same
  codec-resolution path from inputs the upstream regression test does not
  use: more alias spellings and their casing/hyphen variants, different
  conninfo syntaxes (comma style, reordered parameters), and direct calls to
  the low-level codec-resolution entry point; every one of the discriminating
  rows fails at the parent commit and must pass on your tree.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.