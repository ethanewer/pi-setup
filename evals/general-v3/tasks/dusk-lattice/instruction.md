# Reverse-engineer the pixelcast codec

`/app/target/pixelcast` is a compiled, stripped C binary. **You do not have its
source.** It is a scene-postprocessing codec for ASCII (P2) PPM frames. Your
job is to determine exactly what transformation it performs — by running it on
probe inputs you craft yourself, by disassembling it (`objdump -d`, available
in the image together with gcc), by inspecting it under gdb, or any
combination — and then reimplement it in Python so that your reimplementation
is byte-for-byte indistinguishable from the native binary on any valid input.

Work only in `/app`. Do not read `/tests` or `/solution` (they are not present
during your work anyway).

## Fixtures (read-only)

- `/app/target/pixelcast` — the native binary. Do **not** modify, rename, or
  replace it.
- `/app/fixture.ppm` — a supplied sample frame. Do **not** modify it.
- Probe inputs: the binary reads `P2` PPM files (ASCII). Header may contain
  `#` comments and arbitrary whitespace; pixels are decimal values `0..255`,
  three per pixel (R, G, B), row-major, `maxval` must be `255`.

## Deliverables (both required)

1. `/app/reimpl.py` — a runnable Python program:
   ```
   python3 /app/reimpl.py <input.ppm>
   ```
   It must print the **exact bytes** to stdout that
   `/app/target/pixelcast <input.ppm>` writes to stdout, for any valid P2
   input (1x1, non-square, square, extremes `0`/`255`, headers with comments,
   arbitrary but valid whitespace). It must work standalone — it may **not**
   shell out to, link against, or read `/app/target/pixelcast` at run time.
   Standard library only; no network.

2. `/app/notes.md` — your reverse-engineering findings. At minimum it must
   state: the geometric operation applied to the pixel grid (including its
   direction), the per-channel value transform (the exact mapping and how you
   determined it), what happens to the channel order, and the exact output
   serialization format (header layout, separators, line structure).

## How to investigate

The binary is deterministic and self-contained: it reads one PPM (path given
as `argv[1]`) and writes the transformed frame to stdout, exiting non-zero on
malformed input. Useful probes: a 1x1 frame sweeping single channel values (to
recover the per-value mapping), a 2x1 and 1x2 frame (to pin down geometry and
orientation), a frame with three distinct channel values (to detect channel
reordering), and headers polluted with comments/whitespace (to learn how
strict the parser is). Error behavior on invalid input (bad magic, wrong
maxval, out-of-range values, truncated data) does not need to be reproduced —
only valid inputs are graded.

## Grading

The verifier executes `/app/reimpl.py` on the visible fixture and on several
hidden frames and requires byte-identical stdout against reference outputs
produced by the native binary. An incomplete reverse model — e.g. getting the
geometry but not the value transform, or the value transform but not the
channel order or the exact whitespace in the output — will not match and will
fail. `/app/notes.md` must exist and be substantive.
