# Port a DOOM-style frame generator to MIPS and run it through the VM runner

`/app` is a small **cross-compilation** project: a "DOOM style" paletted frame
generator (`gfx/draw.c`) must be **cross-compiled to MIPS** and executed under a
MIPS VM. As shipped, the build uses the **wrong endianness toolchain**, and the
generator has a **rasterizer defect**, so the produced binary never emits the
required frame. Your job is to repair the project so that the produced **MIPS
ELF** binary, run through the supplied runner, emits an exactly specified frame.

## What is in /app

- `gfx/draw.c` — the generator source (paletted framebuffer, 64x24 at 1 byte
  per pixel, plus a 6-byte header; written to stdout in one `write()`).
- `Makefile` — drives the cross-compile and the run (`make`, `make run`).
- `tools/abi.txt` — the **authoritative target-ABI manifest** for this project.
  Read it first.
- `tools/run.js` — the **runner**: a Node.js program that enforces the ABI of a
  candidate binary, then runs it under the QEMU-user MIPS VM
  (`qemu-mips`), forwarding the guest's stdout to its own stdout, and printing
  a SHA-256 of the guest output to stderr.

## Target ABI (also in tools/abi.txt)

- MIPS, **big-endian**, ELF32, `e_machine = 8` (EM_MIPS), o32 ABI, **static**
  link.
- Toolchain prefix for this ABI: `mips-linux-gnu-` (the little-endian
  `mipsel-linux-gnu-` prefix is also installed on purpose).

## Frame the generator must emit — exact spec

`draw.c` writes a **1542-byte** byte stream to **stdout in one `write()`
syscall**:

| offset | size | content |
| --- | --- | --- |
| 0 | 2 | u16 magic = `0x4944` (big-endian emits the bytes "ID") |
| 2 | 4 | u32 marker = `0x50574144` (emits "PWAD") |
| 6 | 1536 | 64x24 framebuffer, row-major, one byte per pixel |

The two header words are placed into memory with **typed stores** (`memcpy`),
so their on-disk byte order follows the **target CPU endianness**. In the
big-endian guest the full 6-byte header is exactly the ASCII text `ID PWAD`.

Framebuffer pixel at scanline `y` (0..23), column `x` (0..63):

```
v     = (x * 13 + y * 29 + ((x >> 1) * (y >> 2))) % 256
index = (v >> 4) & 15          # 0..15
pixel = PALETTE[index]
```

where `PALETTE = " .:-=+*#%@&o$OXY"` (16 entries; index 0 is a space). Row 0 is
the **top** scanline; row `y` holds **all W = 64 columns**, byte at
`out[6 + y*W + x]` for `x = 0..63`. The generator must exit 0.

## Desired end state (your success criteria)

1. `make run` cross-compiles `gfx/draw.c` to a MIPS ELF (`/app/out.elf`) and
   runs it through `node tools/run.js out.elf`, capturing the guest stdout into
   `/app/out.dat`.
2. `/app/out.elf` is a **big-endian** ELF32, `machine = 8` (MIPS) binary. The
   runner's ABI check passes (you must NOT see `run.js: ABI check failed`).
3. `/app/out.dat` is exactly **1542 bytes** with
   `sha256 = f84539f45492d43030fbb741f8dc281145d28f6be9665c2e9b1104c778126688`.
   (The runner's stderr line `frame sha256=...` lets you check this without
   leaving the pipeline.)

## Current failures (both are broken on purpose)

- **ABI mismatch.** As shipped, the Makefile sets a **little-endian** toolchain
  prefix. `make run` therefore produces an ELF the runner rejects with an ABI
  diagnostic. Identify the target ABI from the supplied tooling
  (`tools/abi.txt` + the runner's checks) and adapt the build to it.
- **Generator defect.** Once the binary runs, the emitted frame still does not
  match the spec: every row is **one column short**, and its **last byte
  column** holds uninitialized data. Compare the rasterizer loop in
  `gfx/draw.c` against the spec above and fix the off-by-one in the inner
  loop's upper bound. Do not change the header words, palette, or pixel
  formula.

Work in stages, testing the produced binary through the runner after each change
(`make && make run`, then read the `frame sha256=` line on stderr).

## Artifacts to leave in /app

- the fixed `Makefile` and `gfx/draw.c`,
- `/app/out.elf` (MIPS big-endian ELF) and `/app/out.dat` (the correct 1542-byte
  frame, sha256 `f84539f4...`),
- a successful `make run` invocation.

The final check rebuilds everything from your fixed sources and re-runs the
pipeline, so make sure `make clean && make run` reproduces the frame from
scratch.