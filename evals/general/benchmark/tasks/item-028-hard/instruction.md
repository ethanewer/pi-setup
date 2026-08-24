# Run a Broken OCaml/C Run-Length Stream Across a Bootstrap Boundary

`/app` holds a tiny **two-stage** project. Stage 1 is a *bootstrap spec*: an
OCaml program, `spec.ml`, that runs under the OCaml runtime and compiles a fixed
run table (`count, byte` pairs) into the on-disk stream `rcode.dat`
(`[count:u8][value:u8]` per run). Stage 2 is a **C runtime**, `runtime.c`, that
carries its own arena-based memory manager (a "garbage collector") and a
**run-length decoder**: it reads `rcode.dat`, reconstructs the byte stream,
writes it to `out.dat`, and prints a rolling `CHECKSUM` plus `USED`.

**Two bugs** are present. One lies across the OCaml -> C bootstrap boundary;
the other lives inside the C arena collector. The decoded stream must be
correct for the round trip to succeed.

## Your task

1. **Read the project guidance** (`/app/README.md`). Follow it to build and
   run the pipeline (`make`, or the step-by-step commands).

2. **Reproduce the failure.** Run `./runtime` and `python3 verify.py`. The
   runtime's decoded byte stream does not match the spec's run table.

3. **Debug across the bootstrap boundary.** Trace exactly how each run's two
   bytes (`count`, `value`) are produced by the OCaml bootstrap and consumed by
   the C runtime. The spec deliberately contains runs of length **130**, **160**
   and **255**; reason about the width and signedness of the count read on the
   C side.

4. **Inspect the arena collector.** After decoding, `runtime.c` calls its
   collector while the output buffer is still live. The collector must not
   release allocations that are still referenced. Fix the ordering / ownership
   at the smallest correct point. Keep the change focused.

5. **Run and extend a regression.** `tests/test_roundtrip.py` asserts the
   decoded stream, its checksum, and the printed `CHECKSUM` output. Extend it
   with at least one assertion that guards one of the two fixed defects, then
   make the whole suite green:
   ```
   python3 -m pytest /app -q
   ```

6. **Leave the final artifacts** in `/app`: a correct `out.dat`, the generated
   `rcode.dat`, fixed sources, and a passing regression suite.

## Objective success
- `/app/out.dat` byte-for-byte equals the spec run-table expansion (length 552:
  `3` x `0x41`, `160` x `0x42`, `2` x `0x43`, `130` x `0x44`, `1` x `0x45`,
  `255` x `0x21`, `1` x `0x46`).
- The checksum of `/app/out.dat` is consistent with that stream (`CHECKSUM` on
  stdout matches).