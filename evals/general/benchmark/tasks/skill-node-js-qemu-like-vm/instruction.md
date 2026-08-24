# Tiny CPU emulator (VM) in Node.js

`/app/program.bin` is a binary program for a tiny virtual CPU. Your job is to write a small
**QEMU-like virtual machine** in **Node.js** that fetches, decodes and executes each
instruction of this program, and prints the resulting numbers.

## ISA (fixed, little-endian throughout)

The VM has **8 registers** named `r0`..`r7`, each holding a 32-bit unsigned integer, all
initialized to `0`. There is no memory, stack, or conditional logic.

Every instruction is exactly **12 bytes**: `opcode` (uint32 LE), `rA` (uint32 LE), `rB` (uint32 LE).

| opcode | mnemonic | behavior |
|--------|----------|----------|
| 1 | `LOADI` | `rA := rB` (rB is used as the immediate value) |
| 2 | `ADD`   | `rA := rA + rB` |
| 3 | `SUB`   | `rA := rA - rB` |
| 4 | `PRINT` | print `rA` as a decimal integer followed by a newline to stdout |
| 5 | `MOV`   | `rA := rB` (rB is read as a register index) |

`program.bin` contains a whole number of instructions (no padding; 12 bytes each).

## Task

1. Write `/app/vm.js` — a Node.js program that reads the bytecode file given as its
   first command-line argument, executes every instruction in order, and writes the
   `PRINT` results to **stdout**, one integer per line.
2. Run it: `node /app/vm.js /app/program.bin > /app/output.txt`
3. `/app/output.txt` must exist after the run and contain the exact printed output
   (one integer per line, final newline).

Use `Buffer.readUInt32LE` / `Buffer.writeUInt32LE` (or equivalent) for the fixed 12-byte
little-endian instruction format. Do not modify `/app/program.bin`.
