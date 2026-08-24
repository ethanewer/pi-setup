# RLE Runtime Round-Trip Project

A small two-stage project in `/app`:

1. **Bootstrap spec (OCaml runtime)** — `spec.ml` compiles a fixed run table into
   the binary stream `rcode.dat`. Format, 2 bytes per run:

       [count:u8][value:u8]

   Runs longer than 255 are split by the spec as multiple pairs. `spec.ml` is
   the layout *contract*; you should not need to edit it.

2. **Runtime (C)** — `runtime.c` contains a tiny arena-based memory manager and
   an RLE decoder. It reads `rcode.dat`, reconstructs the byte stream, writes it
   to `out.dat`, and prints a rolling `CHECKSUM=XXXX`.

## Build / run

From `/app`:

    make          # builds rcode.dat (OCaml), compiles runtime (C), runs it
    make check    # just (re)runs the runtime

or step-by-step:

    ocaml spec.ml          # -> rcode.dat
    gcc -std=c99 runtime.c -o runtime
    ./runtime              # -> out.dat + prints CHECKSUM

## The bug

The decoded output does not reproduce the stream the spec encodes. Debug this
**across the bootstrap boundary**: run the stages, compare the runtime's
`out.dat` / checksum to what the spec's run table implies, and trace how each
byte of a run's count/value is interpreted when it crosses OCaml -> C.

Apply the smallest correct source change (in `runtime.c` or `spec.ml`), rebuild,
and confirm:

- `out.dat` byte-for-byte reproduces the run table expansion, and
- the program's `CHECKSUM` on stdout and its `USED` byte count are correct.

There is a `verify.py` helper that reports a mismatch index without revealing
the whole stream. Use it while you debug.