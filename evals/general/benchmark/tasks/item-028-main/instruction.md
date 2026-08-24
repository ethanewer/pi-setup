# Reconstruct a Run-Length-Encoded Stream Across an OCaml/C Bootstrap Boundary

`/app` holds a small two-stage project (see `/app/README.md`). Stage 1 is the
**bootstrap spec** — an OCaml program (`spec.ml`) that runs under the OCaml
runtime and compiles a run table (pairs of `{count, byte}`) into `rcode.dat`.
Stage 2 is a **C runtime** (`runtime.c`) with a tiny arena-based memory manager
("garbage collector") and a **run-length** decoder. It reads `rcode.dat`,
reconstructs the encoded byte stream, writes it to `out.dat`, and prints a
rolling `CHECKSUM` plus an `USED` byte count.

## Your task

1. **Read the project build guidance** (`/app/README.md`). Follow it to build
   and run both stages (`make` or the step-by-step commands).

2. **Debug across the bootstrap boundary.** Run the pipeline. The decoded
   stream currently does **not** match what the spec encodes. Trace each byte of
   a run's `count` / `value` as it is produced by the OCaml bootstrap and then
   interpreted by the C runtime, and locate the discrepancy. `verify.py` prints
   only a mismatch index / lengths so you can iterate without spoiling answers:
   ```
   python3 verify.py
   ```

3. **Make the smallest focused source change** in `runtime.c` (or, if warranted,
   `spec.ml`) so the decoded stream is correct. Keep the change minimal — do not
   rewrite the arena manager or the decoder architecture unless the bug requires
   it. Keep a focused source change and nothing incidental.

4. **Verify with a regression.** After rebuilding, `out.dat` must reproduce the
   run-table expansion **byte for byte**, and the printed (stdout)
   `CHECKSUM`/`USED` must be consistent with that expansion. Re-run the build,
   `./runtime`, and `python3 verify.py` until they agree. Leave the final
   artifacts in `/app` (`out.dat` must be present).

The arena memory manager, run-length format, and the OCaml bootstrap are all
part of the scenario; understand how data moves across the OCaml runtime -> C
runtime boundary before editing. The grader recomputes the exact expected stream
independently.

## Objective success
- `/app/out.dat` exists and byte-for-byte equals the run-table expansion
  described in the project README.
- The checksum implied by `out.dat` matches (`CHECKSUM` shown by a correct run).