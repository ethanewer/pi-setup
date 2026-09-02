# Hollow Keystone — C fix, leak-free, one sanctioned file, clean branch merge

You are working inside `/app` in a container. There are two independent pieces of
work that both must be completed and verified. Read the whole contract first.

## Repository being fixed

A small C utility lives in `/app/src`. Files:

- `src/fixed.c` — the program's main logic (this is the **sanctioned file**).
- `src/tokens.c` — a buffered line reader (`read_line`), provided and correct.
- `src/tokens.h` — its header.
- `src/Makefile` — `make -C /app/src` builds `kvcat` from `fixed.c tokens.c`.
- `/app/sample.conf` — a small token file used for a sanity check.

The tool `kvcat` is invoked as `/app/src/kvcat <file>`. It reads a token file one
line at a time. A **valid** line is exactly `WORD=NUM` where:

- `WORD` is `[A-Za-z][A-Za-z0-9_]*` (first char a letter, then letters/digits/underscore),
- `NUM` is a non-empty run of decimal digits (an unsigned integer),

and nothing else on the line (no trailing spaces, no second `=`, no non-digits after
the number). Any other line — empty, leading digit, no `=`, empty value, non-digit
value, trailing junk, a bare word — is **malformed**.

For a correct run, `kvcat` must:

1. Process **every** line of the file. A malformed line must **not** stop processing:
   the run continues through the rest of the file.
2. Accumulate, per distinct `WORD`, the sum of all its `NUM` values across the whole
   file (case-sensitive: `foo`, `Foo`, `FOO` are three distinct words; `alpha=1`
   and `alpha=3` sum to `alpha=4`).
3. When reading is done, print one line `sum:<WORD>=<total>` per distinct word in
   ascending ASCII/lexicographic order, then a final line `errors:<count>` where
   `<count>` is the number of malformed lines. Example valid output:
   ```
   sum:alpha=15
   sum:beta=4
   sum:gamma=7
   errors:0
   ```
4. Free every allocation it makes before returning. The program must pass a Valgrind
   `--leak-check=full` run with **zero definite leaks** and **no suppression file**
   and **no premature `exit()`/short-circuit** that skips cleanup.

### The shipped bug (in `src/fixed.c`)

The shipping copy of `fixed.c` is buggy: on the **first malformed line** it frees the
current line buffer and immediately `return`s from `kvsum` with `-1`. Consequences:

- It **leaks** every record accumulated so far (the `rec` array and all `key`
  strings are never freed), so Valgrind reports definite leaks.
- It **skips** the rest of the file, so valid records after the first bad line are
  never processed.

Your task is to repair `kvsum` in `src/fixed.c` so a malformed line is counted with
`errors` and processing continues, and so the full cleanup path (free every `key`,
free the `rec` array, free the line buffer) always runs before returning `0`. Do not
cheat: the fix must be real cleanup in source, not `exit(0)`, not a suppression file,
not an environment override, not an `LD_PRELOAD` shim.

### Hygiene rules (enforced byte-for-byte)

- **Only `/app/src/fixed.c` may be modified.** `src/tokens.c`, `src/tokens.h`,
  `src/Makefile`, and `/app/sample.conf` must remain **byte-identical** to their
  original bytes.
- Do not create, rename, or delete any source/config file in `/app` or `/app/src`.
  The build artifact `/app/src/kvcat` is expected; nothing else new is tolerated.
- The repair must live in source (`fixed.c`), never in runtime configuration.

### Building

Run `make -C /app/src` to produce `/app/src/kvcat`. It must compile cleanly with the
provided Makefile (`gcc -g -O0 -Wall -Wextra -std=c11`). After your fix, sanity-check
against the visible sample and with Valgrind (it must report no definite leaks).

The verifier will recompile `kvcat` from your delivered `fixed.c` and run it (under
Valgrind) on the visible `sample.conf` **and on several hidden token files** — mixing
valid and malformed lines, CRLF line endings, a file whose last line has no trailing
newline, uppercase vs lowercase words, words with leading digits, and an
all-malformed file — comparing stdout byte-for-byte and requiring no definite
leaks in every case.

## The git merge

`/app/devzone` is a git repository that two engineers forked from a common ancestor
commit. The working tree's current files at the common ancestor are also snapshotted
under `/opt/frozen/base/` (`config.toml`, `deps.txt`, `NOTES.md`). Two branches
diverge from that ancestor:

- `rel-main` — a release-hardening branch.
- `feat-stream` — a streaming-feature branch.

Both branches edited `config.toml` and `deps.txt`, so a merge between them produces
conflicts you must resolve.

`config.toml` is a TOML file containing a `[profile]` table with keys `buffer`,
`mode`, and optionally `stream`:

- The ancestor has `buffer = 64`, `mode = "auto"`, and **no** `stream` key.
- `rel-main` set `buffer = 1024` and `mode = "turbofan"`.
- `feat-stream` set `buffer = 256` and added `stream = true` (keeping `mode = "auto"`).

**Resolution rule for `config.toml`:** where both branches changed the same key, take
`rel-main`'s value; where only one branch introduced a key, keep it. So the merged
`[profile]` table must be exactly:

```
[profile]
buffer = 1024
mode = "turbofan"
stream = true
```

`deps.txt` is a dependency list, one `name=version` pin per line:

- The ancestor has `server=4.2.1` and `cache=2.3.0`.
- `rel-main` changed `cache` to `2.9.0` (still has `server=4.2.1`).
- `feat-stream` changed `cache` to `2.6.0`, kept `server=4.2.1`, and added `monitor=9.7.2`.

**Resolution rule for `deps.txt`:** for every dependency name present in either
branch, pin exactly one version — the **highest** version among the branches that
reference that name — and write the lines **sorted by name** (ASCII ascending). So the
merged `deps.txt` must be exactly:

```
cache=2.9.0
monitor=9.7.2
server=4.2.1
```

Perform the merge inside `/app/devzone` (your choice of base branch), resolve the
conflicts per the rules above, and commit the result so the working tree has **no**
unmerged paths and **no** conflict markers.

## Deliverables (all must exist after you finish)

1. `/app/src/fixed.c` — repaired, the only modified source file.
2. `/app/src/kvcat` — built from the repaired source.
3. `/app/merged.diff` — the full change the merge introduced relative to the common
   ancestor, such that applying it to a pristine copy of the ancestor files (the
   contents of `/opt/frozen/base/`) reproduces your merged `config.toml` and
   `deps.txt`. It must contain no conflict markers. A reliable way to produce it is
   to diff the pristine ancestor snapshot against your merged working files, e.g.:
   ```
   cd /opt/frozen/base
   diff -u config.toml /app/devzone/config.toml >  /app/merged.diff
   diff -u deps.txt    /app/devzone/deps.txt    >> /app/merged.diff
   ```
   (Note: a plain `git diff $(git merge-base rel-main feat-stream) HEAD` is *not*
   reliable after a merge, because the merge-base can collapse onto the merged-in
   branch; diffing the `/opt/frozen/base` snapshot directly guarantees the file can
   reconstruct from the ancestor).
4. `/app/deps.lock` — the merged dependency-set pins, exactly the resolved
   `deps.txt` content above (`cache=2.9.0`, `monitor=9.7.2`, `server=4.2.1`, sorted by
   name, exact `name=version` lines with no wildcards or ranges).

Everything is checked automatically against these exact contents and the rules above.
Do not modify anything outside the sanctioned deliverables and `/app/devzone`. Good
luck.
