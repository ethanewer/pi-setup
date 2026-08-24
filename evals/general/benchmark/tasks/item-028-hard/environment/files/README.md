# RLE Round-Trip Project (two bugs)

A two-stage project in `/app/`:

1. **Bootstrap spec (OCaml runtime)** — `spec.ml` compiles a fixed run table
   into `rcode.dat`. Format, 2 bytes per run: `[count:u8][value:u8]`.
   `spec.ml` is the layout contract; do not edit it.

2. **C runtime** — `runtime.c` RLE-decodes `rcode.dat`, writing `out.dat` and
   printing `CHECKSUM` / `USED`. It also contains a tiny arena-type
   "garbage collection" memory stage.

## Build / run

    make                 # build rcode.dat (OCaml) + runtime (C), run runtime
    ./runtime
    python3 verify.py    # reports mismatch index/lengths (does not spoil stream)

Or use pytest on the shipped regression suite:

    pytest -q tests/test_roundtrip.py

## The bugs (both are real)

1. The C runtime reads each run's **count byte as a signed char**, so counts of
   128..255 are misread as negative and the run is mis-decoded (this stream
   deliberately uses counts above 127: 130, 160, 255).

2. The arena **collector runs before the decoded output has been written** and
   it reclaims (scrubs) the very slot that still holds the current, live output
   buffer. Is the collector supposed to touch live (referenced) objects?

Trace how run `count` / `value` bytes cross the OCaml -> C boundary, then
account for what the collector releases and when. Apply focused changes in
`runtime.c` (expected), rebuild, and make the round-trip and all regression
tests green.

## Definition of a correct run
- `out.dat` byte-for-byte equals the run-table expansion:
  `(3 * 0x41) (160 * 0x42) (2 * 0x43) (130 * 0x44) (0x45) (255 * 0x21) (0x46)`.
- printed `CHECKSUM` (stdout) and `USED` match that output.