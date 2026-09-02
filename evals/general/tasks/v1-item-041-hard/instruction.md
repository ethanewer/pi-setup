# Port a DOOM-style framebuffer renderer to MIPS and run it through the VM runner

`/app` contains a small cross-compilation project: a **DOOM generic** paletted
framebuffer renderer (`doom/frame.c`) that must be **cross-compiled to MIPS**
and executed under a MIPS VM. The build and the renderer are **both currently
broken** against the required target ABI. Your job is to repair the project so
that the produced **MIPS ELF** binary, run through the supplied runner,
emits an exactly specified frame.

## What is in /app

- `doom/frame.c` — the renderer source (paletted framebuffer, 64x32 at 1 byte
  per pixel, plus a 6-byte header).
- `Makefile` — drives the cross-compile and the run (`make`, `make run`).
- `tools/abi.txt` — the **authoritative target-ABI manifest** for this
  project. Read it first.
- `tools/run.js` — the **runner**: a Node.js program that checks the ABI of a
  candidate binary, then executes it under the QEMU-user MIPS VM
  (`qemu-mips`), forwarding the guest's stdout to its own stdout. It prints
  diagnostics (including a SHA-256 of the guest's output) to stderr.

## Target ABI (also in tools/abi.txt)

- MIPS, **big-endian**, ELF32, `e_machine = 8` (EM_MIPS), o32 ABI, **static**
  link.
- Toolchain prefix for this ABI: `mips-linux-gnu-` (installed in the image).

## The frame the renderer must emit — exact spec

`frame.c` computes a 2054-byte byte stream and writes it to **stdout in one
`write()` syscall**:

| offset | size | content |
| --- | --- | --- |
| 0 | 2 | u16 magic = `0xE1B0` |
| 2 | 4 | u32 marker = `0x444F4F4D` (*"DOOM"* in ASCII) |
| 6 | 2048 | 64x32 framebuffer, row-major, byte per pixel |

The two header words are placed into memory with **typed stores** (`memcpy`),
so their on-disk byte order follows the **target CPU endianness**. In a
big-endian guest the header bytes are exactly `E1 B0 44 4F 4F 4D`.

Framebuffer pixel at scanline `y`, column `x`:

```
v     = (x*7 + y*13 + ((x*y) >> 2)) % 256
index = (v >> 4) & 15          # 0..15
pixel = PALETTE[index]
```

where `PALETTE = " .:*oOOO####@@@@"` (16 entries, index 0 = space, 15 = `@`).
Row 0 is the **top** scanline; each row holds **all W = 64 columns**
(`out[6 + y*W + x]` for `x = 0..63`).

The renderer must exit 0.

## The desired state (your success criteria)

1. `make run` cross-compiles `doom/frame.c` to a MIPS ELF 
   (`/app/out.elf`) and runs it through `node tools/run.js out.elf`,
   capturing the guest stdout to `/app/out.dat`.
2. `/app/out.elf` is a **big-endian** ELF32 machine=8 (MIPS) binary. The
   runner's ABI check passes (no `run.js: ABI check failed` message).
3. `/app/out.dat` is exactly 2054 bytes with
   `sha256 = 7a8e00efcf4625b02cff2c49a58a81a48ffbe67eee843e3a25f36ff2b100ac9a`.
   (The `run.js` stderr line `frame sha256=...` lets you check this without
   leaving the pipeline.)

## Current failures (both are broken on purpose)

- **ABI mismatch.** As shipped, the Makefile builds with the wrong endianness
  toolchain. `make run` will produce an ELF that the runner rejects with an
  ABI diagnostic. Identify the ABI from the supplied tooling
  (`tools/abi.txt` + the runner's checks) and adapt the build to it.
- **Renderer defect.** Once the binary runs, the emitted frame still does not
  match the spec: every row is shifted left by one column and its last byte
  is garbage. Compare the rasterizer loop against the spec above and fix the
  defect in `frame.c` (a one-line change in the inner loop bound). Do not
  change the header, palette, or pixel formula.

Work in stages, testing the produced binary through the runner after each
change (`make && make run`, then check the `frame sha256=` line).

## Artifacts to leave in /app

- fixed `Makefile` and `doom/frame.c`,
- `/app/out.elf` (MIPS big-endian ELF), `/app/out.dat` (the correct 2054-byte
  frame, sha256 `7a8e00ef...`),
- a successful `make run` invocation.

The final check rebuilds everything from the fixed sources and re-runs the
pipeline, so make sure `make clean && make run` reproduces the frame from
scratch.