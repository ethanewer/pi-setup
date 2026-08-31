# Vellum Press spill-buffer reclaim

A render node at **Vellum Press** rotates its frame spill files: the spool
manager opens a frame buffer, then unlinks its path while the process is still
running (a common log-rotation pattern), so the data survives only as an
**open file descriptor to an unlinked file**. You must write a small reusable
reclaim tool and use it to recover the live buffer byte-for-byte.

## Environment

- Working directory: `/app`. A keeper process (`/app/latch_keeper.py`) was
  started at container boot; it holds open descriptors and **never exits**.
  - It records its PID in `/app/spool/.latch.pid` (plain text, just the PID).
  - It holds one descriptor to an **unlinked** file (its `/proc/<pid>/fd/N`
    link target ends with `(deleted)`) — this is the payload to recover.
  - It also holds one or more descriptors to files whose paths **still exist**
    (e.g. `/app/spool/manifest.txt`) — these are decoys; do not confuse them
    with the target.
- Python 3.12 is available as `python3`; standard library only.
- **Do not kill the keeper process and do not modify anything under `/app/spool`.**

## Deliverables (both required)

1. `/app/reclaim_fd.py` — a runnable Python program with this interface:
   ```
   python3 /app/reclaim_fd.py <pidfile> <output_path>
   ```
   It reads the PID from `<pidfile>`, scans `/proc/<pid>/fd/`, locates the
   descriptor whose link target ends with `(deleted)`, and writes that
   descriptor's **full content, byte-for-byte**, to `<output_path>`.
   Exactly one such deleted descriptor exists for any keeper this tool will be
   run against. It must exit with status 0 on success.

2. `/app/reclaimed_payload.bin` — the output of running your tool on the live
   keeper:
   ```
   python3 /app/reclaim_fd.py /app/spool/.latch.pid /app/reclaimed_payload.bin
   ```

The grader re-runs `/app/reclaim_fd.py` against **fresh keeper processes** with
different payload contents, sizes, pidfile locations, and decoy files, so the
tool must be general — do not hard-code the visible PID, fd numbers, paths, or
contents.

## How to recover the content

For each numeric entry `N` in `/proc/<pid>/fd/`:
- `os.readlink('/proc/<pid>/fd/N')` returns the target path; a descriptor to an
  unlinked file ends with `(deleted)`.
- Open `/proc/<pid>/fd/N` (e.g. `open(..., 'rb')`) and read it to EOF: this
  returns the content of the still-open inode, even though the name is gone.

Ignore non-numeric entries, descriptors you cannot stat/read, and descriptors
whose target does not end with `(deleted)`.

## Edge cases the grader probes

- Decoy descriptors whose paths still exist (must be ignored).
- Different payload sizes, from ~1 KiB to ~12 KiB.
- A pidfile at an arbitrary path; the fd number of the deleted file varies.
- Extra open descriptors (pipes, the keeper's own modules) that must be skipped
  without crashing.

## Constraints

- Standard library only; no network access.
- The tool must never read `/tests`, `/solution`, or checker data.
- Never kill the keeper; just read from `/proc`.
