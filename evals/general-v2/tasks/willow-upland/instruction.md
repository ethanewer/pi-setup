# Willow Upland — a data-ingest pipeline helper

You are on the **Willow Upland** data-ingest team. The nightly build runs on a plain
Linux box; your job is to finish two deliverables so it can run end-to-end:

1. `/app/fix.sh`
2. `/app/Makefile`

The verifier checks **every** requirement below, and it re-runs your deliverables on
**fresh hidden fixtures** as well as the visible sample. **Do not hard-code** the
contents of the shipped logs or the visible artifact names.

## What already exists in `/app`

| Path | Contents |
|------|----------|
| `/app/logs/` | raw source **log files** (each named `*.log`). There may be several. This is the scan input. |
| `/app/stage/` | a build workspace of **generated artifacts**: `*.tmp`, `*.stage`, `*.part`, `*.o`, `*.bin`, `*.so`, `*.delta`, `*.map`, plus the allowed `*.proof` files, a `MANIFEST`, and a `scratch/` subdirectory. |
| `/app/src/serial.c`, `/app/src/pgen.c` | two C source files the Makefile must compile. |

`/app/out`, `/app/bin` do not exist yet — your deliverables create what is needed.

## Deliverable 1 — `/app/fix.sh`

An executable shell script. Running `bash /app/fix.sh` must:

1. **Recreate the directory structure idempotently.** Ensure `/app/out/records`,
   `/app/out/summary`, `/app/stage`, and `/app/logs` all exist, no matter whether the
   tree is empty, partially built, or complete. Running it again in a row must succeed,
   produce byte-identical output, and must **not** delete or corrupt any file already
   present (for example a file already inside `/app/out/records/` must survive).

2. **Scan all log files for severity tokens.** Glob **all** `/app/logs/*.log`. For each
   of the three severity tokens `INFO`, `WARN`, `ERROR`, count the total number of log
   **lines** that carry that token, and write the result to
   `/app/out/summary/severity_counts.txt` — exactly one line per token, in this
   byte-exact format (order `INFO`, `WARN`, `ERROR`, LF newlines):

   ```
   INFO=6
   WARN=2
   ERROR=4
   ```

   Counting rules (authoritative; the verifier recomputes them with the same semantics):

   * A token carries a line when it appears as a **standalone word** — a maximal run of
     letters/digits/underscore — matched **case-insensitively**. So `warn`, `WARN`, `WaRn`
     all count for `WARN`; `info`/`Info`/`INFO` count for `INFO`.
   * Matching is whole-word with a real word boundary on both sides: the longer word
     `WARNING` does **not** count as `WARN` (after the `WARN` run the next char `I` is a
     word character, so there is no boundary) while a bare `WARN over budget` **does**,
     and `errors` does not count as `ERROR` (the trailing `s` is a word character).
   * One line can advance **more than one** severity at once (a line that mentions both
     `WARN` and `ERROR` adds to each total).
   * Only line *contents* matter; a filename that contains a token is irrelevant.

3. **Regenerate its output cleanly.** Running `bash /app/fix.sh` from scratch must exit
   with status 0 and leave a **non-empty** `/app/out/summary/severity_counts.txt`.
   Re-running overwrites it with identical bytes.

4. **Clean generated artifacts to the allowed file set.** Inside `/app/stage`, delete
   every file that is **not** allowed. The allowed set is: (a) any file whose name ends
   in **`.proof`**, and (b) the literal file **`MANIFEST`**. Delete everything else
   (`*.tmp`, `*.stage`, `*.part`, `*.o`, `*.bin`, `*.so`, `*.delta`, `*.map`, …).
   Preserve the `scratch/` subdirectory **and its contents** untouched. Hidden fixtures
   use different intermediate suffixes, so the rule must be suffix-based, not name-based.

### scripted allowlist constraint (strict / static-sanitized)

`/app/fix.sh` must stay on the following **allowlist** — build the whole approach with
only these utilities and control forms:

* utilities: `mkdir`, `rm`, `grep`, `wc`, `printf`, `cat`, `cp`, `test` / `[`
* control: `for … in … do … done`, `if … then … else … fi`, `case … esac`,
  `>` / `>>` redirection, and `|` pipelines.

Forbidden (the static sanitizer fails the task if any occurs):

* command substitution `$(...)`
* backticks `` `...` ``
* process substitution `<( ... )`
* the words `eval`, `xargs`, `awk`, `perl`, `python`, `ruby`, `tee`, `sed`, `sort`,
  `uniq`, `find`, `sudo`, `tr`, `source`, `wget`, `curl`, `nc`, `dd`.

All the required behaviour is achievable with the allowed set alone — no variables,
arithmetic, or command substitution are needed. Also, `/app/fix.sh` must:

* start with the exact first line `#!/usr/bin/env bash`
* use **LF-only** line endings (no `\r` bytes anywhere). Do not save it with CRLF.

## Deliverable 2 — `/app/Makefile`

A `make` workflow with `serial` and `pgen` targets that compile the two supplied
sources. From a run with no prior build it must:

* compile `/app/src/serial.c` → executable `/app/bin/serial`
* compile `/app/src/pgen.c` → executable `/app/bin/pgen`
* make a default-goal run succeeds and builds **both**.
* Re-running `make` is a clean no-op (“up to date”) that still exits 0 and leaves both
  binaries present, and `make clean` followed by `make -j2` rebuilds both from scratch.

Each program just prints a short line; success requires the executables to be runnable
and to print something containing the strings `SERIAL` and `PGEN` respectively. Use
`gcc` (already installed). The Makefile must genuinely **compile from** `/app/src/…`,
not emit prebuilt bytes.

## Deliverables recap
* `/app/fix.sh` — idempotent, LF-only, allowlist-restricted; produces the severity
  table and cleans `/app/stage` to the allowed set.
* `/app/Makefile` — builds `/app/bin/serial` and `/app/bin/pgen` from `/app/src`.

Both must exist under `/app`, and be runnable by the verifier exactly as described.

## Do not modify
* Leave `/app/src/serial.c` and `/app/src/pgen.c` exactly as shipped.
* Do not read `/tests` or `/solution`. Your deliverables must stand on their own.

Make a clean exit-0, keep `bash /app/fix.sh` quiet, and do not use any of the forbidden words above.