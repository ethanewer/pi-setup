# Rebuild the archive skeleton from a checksum catalog

The photo-archive staging area at `/app` holds a **checksum catalog**,
`/app/catalog.txt`, describing a file tree whose payload was lost in transit.
Before the next sync pass, the **empty skeleton** of that tree must be
recreated locally: every path listed in the catalog must exist as a real file
of **zero bytes**, with all implied directories in place. The sync tool
re-scans the skeleton and compares it against the catalog, so a single missing
or misplaced leaf file — or any stray extra file — makes the rescan mismatch.

## Deliverable

Write one reusable program, `/app/skeleton.py`, invoked as:

```
python3 /app/skeleton.py <catalog> <outdir>
```

It must work on **any** catalog conforming to the format below, not just the
shipped one — the verifier re-runs it on fresh hidden catalogs.

## Catalog format (exact)

The catalog is plain UTF-8 text, in the style of `sha256sum` output:

- A **valid entry** is a line of the form
  `<64 lowercase hex characters><two spaces><path>`
  e.g. `9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08  photos/2029/beam walk/IMG_0001.raw`
  The `<path>` is everything after the **first** two-space run following the
  hex digest; it may itself contain single spaces. The digest is not used for
  reconstruction (files are empty), but it is part of the syntax and must be
  present and well-formed for the line to count as an entry.
- Every valid entry is a **file** (leaf) entry. Directories are **not** listed
  explicitly; they are implied by the file paths and must be created as needed.
- A line that is empty or contains only whitespace is **ignored**.
- A line whose first non-space character is `#` is a **comment** and is
  ignored.
- Any other line is **malformed**.

## Behavior

1. **Validate the whole catalog first.** If any problem below is found, print a
   clear message to stderr, exit with a **non-zero** status, and create
   **nothing** under `<outdir>` (no files, no directories):
   - a malformed line,
   - a path that is absolute (starts with `/`),
   - a path with any `..` component,
   - a **file/directory conflict**: one entry's path would have to serve as a
     directory for another entry (e.g. entries `a` and `a/b` — `a` is both a
     file and a parent directory). Two identical duplicate entries are fine.
2. On success (exit `0`): for every file entry, ensure
   `<outdir>/<path>` exists as a **regular file of exactly zero bytes**
   (an existing file at that path is truncated to zero bytes), with all parent
   directories created. Running the program twice must be safe (idempotent)
   and change nothing.

## Visible run

Run it on the shipped catalog so the skeleton lands in `/app`:

```
python3 /app/skeleton.py /app/catalog.txt /app/skeleton
```

This must leave the `/app/skeleton` tree in place.

**Do not modify `/app/catalog.txt`** — it is re-checked byte-for-byte.

## Hidden cases the verifier probes

- Deeply nested paths, names containing spaces, and duplicate entries
  (idempotent re-run).
- A catalog containing only comments/blank lines: `<outdir>` must end up
  empty (no files) and the program must exit `0`.
- A catalog with an absolute path: non-zero exit, nothing written.
- A catalog with a `..` component: non-zero exit, nothing written.
- A catalog with a file/directory conflict: non-zero exit, nothing written.
- A catalog with one malformed line among valid ones: non-zero exit, nothing
  written.

## Constraints

- Python 3.12 standard library only; no network at verify time.
- The verifier executes `/app/skeleton.py` unchanged on every case, so the
  program must not hard-code the shipped catalog's contents.
