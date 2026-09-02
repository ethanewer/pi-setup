# Build an instruction assembler for TAL-3

Write a real, reusable **assembler** that translates programs written in
the TAL-3 instruction language (specified in `/app/ISA.txt`) into
machine-code bytes, and run it on the provided source to produce a
binary. Read `/app/ISA.txt` first — it is the authoritative spec.

## Deliverables

Create exactly these artifacts under `/app`:

1. **`/app/assemble.py`** — a Python 3 command-line program invoked as

   ```
   python3 /app/assemble.py <SOURCE_SRC> <OUTPUT_BIN>
   ```

   It must read the TAL-3 source file given as the first argument,
   assemble it, and write the encoded bytes to the file path given as
   the second argument. It must work for **any** source file that
   conforms to the grammar in `/app/ISA.txt`, not just the provided
   example. On success it returns exit status `0` and writes nothing to
   stdout. On any error condition listed in `/app/ISA.txt` it must
   return a **nonzero** exit status, print a diagnostic to stderr that
   includes the offending physical line number, and must not create the
   output file.

2. **`/app/program.bin`** — the machine-code bytes produced by running
   your assembler on the visible program:

   ```
   python3 /app/assemble.py /app/program.src /app/program.bin
   ```

## Inputs

- `/app/ISA.txt` — the complete language specification (opcode
  encodings, source grammar, and the error rules). Read it in full.
- `/app/program.src` — the visible program you must compile.

## What your assembler must handle

- Label definitions, including a label on its own line, and **forward
  references** (a `JMP` may target a label defined later in the file).
- Blank lines and `#` comments.
- Register operands across the whole range `r0`..`r15`.
- Immediate operands written in decimal or `0x` hex, including boundary
  values `0` and `255`.

It must **reject** every one of the following malformed inputs with a
nonzero exit status and a line-numbered diagnostic on stderr (the
hidden cases probe all of these):

- an unknown mnemonic,
- a duplicate label definition,
- the wrong number of operands for a mnemonic (e.g. `HALT 5`),
- a register operand outside `r0..r15` or that is not a register (e.g.
  `ADD r16, r0`, or a bare number used as a register),
- an immediate that is not a number or is outside `0..255` (e.g.
  `LOAD r2, 300`),
- a `JMP` operand that is not a defined label (e.g. `JMP nowhere`).

## Rules

- **Do not modify** `/app/ISA.txt` or `/app/program.src`.
- Each instruction is fixed length; instruction lengths and encodings
  are taken from `/app/ISA.txt`. JMP addresses are 16-bit big-endian.
  `ADD` packs its two register numbers into one byte (high and low
  nibbles) as described in the spec.
- The environment is fully offline; do not attempt any network access.
- Work only under `/app`. Do not read or write anything outside it.