# Loamware marble-shard: reclaim a deleted-but-open cache shard

The Loamware cache appliance keeps small **shard** payloads on disk. At boot
the `shardd` keeper process opens its shard file and then **unlinks the path
name**, so the payload survives only as an open file descriptor inside that
process. The file name is gone; the bytes are not. You must write a reusable
recovery program that reclaims the content of a named shard by scanning the
live process table — and it must keep working on unseen appliance states.

## Environment

- Working directory: `/app`. It already contains `/app/cache/manifest.txt`
  (shard metadata; the payloads themselves are unlinked at boot) and the
  keeper program `/app/shardd.py` (already running).
- Python 3.12 is available as `python3` (standard library only; no network).
- **Do not kill `shardd` and do not modify anything under `/app/cache/`.**

## Shard file format

A shard payload is a plain-text file whose **first line is exactly**
`SHARD_ID=<id>` (no spaces, no prefix), followed by arbitrary payload lines.

## Deliverables (both required)

1. **`/app/recover.py`** — a reusable Python program with this interface:
   ```
   python3 /app/recover.py <shard_id> <output_path>
   ```
   It must:
   - scan `/proc/*/fd/` for descriptors of **every running process** (do not
     rely on any PID file — none exists) whose link target names a deleted
     file (targets ending in `(deleted)`),
   - read the content behind each such descriptor and select the one whose
     first line is exactly `SHARD_ID=<shard_id>` for the requested id
     (matching the exact marker line — a payload that merely *contains* the id
     string on some other line is a different shard and must not match),
   - write the matched payload **byte-for-byte** to `<output_path>`,
   - exit with status **0** when a shard was recovered and status **2** when
     no deleted-but-open payload with that exact marker line exists. Any other
     failure should exit non-zero as well.
   Descriptors that cannot be read (or that are not regular deleted files)
   must be skipped without crashing.

2. **`/app/recovered.txt`** — the output of running your program on the live
   appliance for the active shard `k7`:
   ```
   python3 /app/recover.py k7 /app/recovered.txt
   ```

The grader re-runs `/app/recover.py` against **fresh appliance states** it
constructs itself (several keeper processes holding different deleted shards
at once, some of them decoys), so the program must be fully generic: no
hard-coded PIDs, paths of the hidden fixtures, or file contents.

## Traps the grader probes

- **Decoy payloads** held by other processes: deleted files that merely
  *mention* the requested id on a later line (e.g. `PREV_SHARD=<id>`) or whose
  marker line is a *different* id that has the requested id as a prefix. Only
  an exact first-line marker `SHARD_ID=<id>` counts.
- **Negative query**: an id that no deleted payload carries — the program must
  exit 2 and must not write a bogus output file.
- Multiple keepers running simultaneously; only one payload matches.

## Constraints

- Standard library only; no network access at solve or verify time.
- Never read `/tests`, `/solution`, or any grader-internal path.
- The verifier runs `/app/recover.py` unchanged on hidden appliance states.
