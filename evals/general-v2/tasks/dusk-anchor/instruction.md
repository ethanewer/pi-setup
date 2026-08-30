# dusk-anchor — standalone clone of the recovered "vellum" transform

The **Skyhook-44** nav unit's boot-stage filter, the **vellum** transform, was
recovered by the RE team and written up in `/app/vellum-spec.txt`. The original
firmware binary is gone (there is no target binary anywhere on this machine);
your job is to reimplement the documented behavior as a **fully standalone C
program** that can be rebuilt and re-run in total isolation.

Work inside `/app`. Do not modify `/app/vellum-spec.txt` or `/app/seed.bin`.

## The recovered behavior (authoritative; `/app/vellum-spec.txt` says the same)

Given an input byte stream `B[0..n-1]`:

1. **Mirror.** Reverse the byte order: `R[i] = B[n-1-i]`.
2. **Cascade.** Maintain an 8-bit key `k`, initialized to `0x5D`. Walk the
   mirrored bytes in order; for each byte `r`:
   - emit `o = r XOR k` (one output byte),
   - then update the key with the **emitted** byte: `k = (k + o + 0x33) & 0xFF`.
3. **Trailer.** After the cascade, append one byte: the XOR of **all** emitted
   cascade bytes. The XOR of an empty set is `0x00`, so an empty input yields
   exactly one output byte `0x00`.

The output stream is: cascade bytes (in emission order) followed by the trailer
byte. Output length is always input length + 1.

## Deliverables (all required)

1. `/app/dusk/app.c` — the C source. Constraints:
   * includes **only** C standard-library headers, using angle brackets —
     no `#include "..."` of any local file, no reference to the `/app` tree,
     to `vellum-spec.txt`, or to any other fixture anywhere in the source;
   * reads the raw byte stream from **stdin** and writes the transformed bytes
     to **stdout** in binary-exact form (handle every byte value `0x00`–`0xFF`,
     including NUL bytes), then exits 0;
   * accepts **arbitrarily long** input (no fixed-size cap) and zero-length
     input;
   * performs no file I/O other than the stdin/stdout streams.
2. `/app/dusk/Makefile` — its default target must build `/app/dusk/app` from
   `app.c` in the directory containing only those two files. `app` must be a
   **statically linked** executable (`-static`; the image supports it).
3. `/app/dusk/app` — the built binary itself.
4. `/app/proof.txt` — the SHA-256 hex digest (lowercase, 64 hex chars) of the
   output produced by running `/app/dusk/app` with `/app/seed.bin` on stdin.
   Produce it by actually running your binary, e.g.:
   ```
   /app/dusk/app < /app/seed.bin | sha256sum
   ```
   and writing just the 64 hex characters into `/app/proof.txt`.

## Isolation contract (graded)

The grader copies **only** `app.c` and `Makefile` into an empty scratch
directory, runs `make` there, and pipes hidden inputs (empty, NUL-bearing,
and large, up to at least 64 KiB) through the freshly built binary. It also
re-runs your delivered `/app/dusk/app` the same way. Any read of another file,
any local include, any build-time or run-time dependency outside the C
standard library makes the run fail. There is no network.

## Verification summary

* clean-room rebuild from only `app.c` + `Makefile` must succeed and produce a
  statically linked `app`;
* the binary's byte output on each hidden input must equal the vellum
  transform of that input exactly (byte-for-byte);
* `/app/proof.txt` must equal the recomputed digest of your binary's output on
  `/app/seed.bin`.
