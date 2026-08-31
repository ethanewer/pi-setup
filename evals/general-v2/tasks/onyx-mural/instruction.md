# Reverse-engineer the `mural` dithering binary

`/app/scene/mural` is a compiled C program with **no source available**. It
reads a grayscale grid and prints an ASCII-art rendering of it. Your job is to
determine **exactly** what transformation it performs and reimplement it in
Python, byte-for-byte.

## Environment

- Working directory: `/app`.
- The target binary: `/app/scene/mural`. **Do not modify, move, or delete it**
  during your work (the verifier relocates it before testing your deliverable,
  so your reimplementation must be fully self-contained).
- Sample grids to probe with are in `/app/grids/` (`sample_mural_a.txt`,
  `sample_mural_b.txt`). You may create your own probe grids anywhere
  (e.g. `/tmp`).
- Tools available: `python3`, `gcc`, `objdump`, `gdb`, `strings`, `file`.

## Target interface

```
/app/scene/mural <grid-file>
```

- **Input** (`grid-file`): whitespace-separated integer tokens. The first two
  tokens are `H` and `W` (height, width, each >= 1 and <= 512). The next `H*W`
  tokens are pixel values in row-major order, each in `0..255`.
- **Output**: printed to stdout. You must discover the exact format (it is
  text, one line per grid row). Try 1x1 grids, tiny grids, and grids with
  extreme values (0, 127, 128, 255) to pin the behavior down.

## Deliverables (both required)

1. `/app/reimpl.py` — a standalone Python 3 program:
   ```
   python3 /app/reimpl.py <grid-file>
   ```
   It must print **byte-identical stdout** to what `/app/scene/mural` prints
   for the same grid file, for **any** valid grid (not just the samples).
   Constraints:
   - Standard library only; no network.
   - It must NOT execute, link, or read `/app/scene/mural` — the verifier
     moves the binary away before running your program, and independently
     computes the expected output. A reimplementation that only partially
     captures the transformation (wrong scan order, wrong weights, wrong
     rounding, wrong output format) will deviate on hidden grids and fail.
   - Do not hard-code outputs for the provided sample grids.

2. `/app/notes.md` — a short write-up documenting what you found: the overall
   operation, the scan order over the grid, any thresholds/constants/weights
   involved, how numeric error/rounding is handled, which neighbors receive
   propagated quantities (and what happens at the borders), and the exact
   output format (characters, separators, trailing newlines).

## How to work

Any combination of black-box probing and static analysis is fair game:
- Craft small probe grids (e.g. single row/column, single nonzero pixel,
  constant-value grids) and diff the outputs.
- `objdump -d /app/scene/mural` and look for the integer constants used by the
  transformation; `gdb` can confirm the loop structure.
- Cross-check your model against the binary on random grids until you are
  confident, then make the program generic.

## Verification

The verifier runs `python3 /app/reimpl.py` on the visible sample grids and on
several hidden grids (varied sizes, boundary values 0/127/128/255, random
fields) and compares stdout byte-for-byte against the reference behavior. It
also checks `/app/notes.md` is a substantive write-up of the operation.
