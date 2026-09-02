# Corvid-8 Flight Computer — Service Manual Extract (rev C)

This extract is the complete hardware reference for the Corvid-8 avionics
board hosted on the bench. The bench emulator host `/app/bench/corvid-emu`
implements exactly what is documented here; it is **generic** and requires a
machine profile describing the board before it will run anything.

## 1. Machine profile

The emulator host is configured entirely by a JSON **machine profile** with
these keys (all required, all integers):

| key                 | meaning |
|---------------------|---------|
| `memory_kib`        | size of the uniform RAM, in KiB |
| `load_address`      | byte address where the program image is loaded |
| `entry`             | initial program counter value |
| `serial_out_address`| address of the serial data register (memory-mapped I/O) |

## 2. Memory

- Uniform RAM of **64 KiB** (see §6 for the exact decimal size; addresses are
  taken modulo the RAM size).
- No ROM banking, no interrupts.

## 3. Program image loading

The loader places the program image at the **EPROM base `0x0200`**. Execution
begins at the **load address** (the first byte of the image).

## 4. Memory-mapped I/O

The sole I/O device is the serial data register **SDATA at `0xF000`**
(write-only). A write to SDATA (the `OUT` opcode) transmits the accumulator as
**unsigned decimal ASCII followed by a single line feed**.

## 5. Instruction set

All multi-byte fields are **16-bit, unsigned, little-endian**. The accumulator
`A` is a 16-bit unsigned value (0..65535); ADD/SUB/MUL wrap modulo 65536.

| opcode | bytes | mnemonic | semantics |
|--------|-------|----------|-----------|
| `0x00` | 1 | `NOP`  | no effect |
| `0x10` | 3 | `LDA`  | `A = imm16` |
| `0x11` | 3 | `ADD`  | `A = (A + imm16) mod 65536` |
| `0x12` | 3 | `SUB`  | `A = (A - imm16) mod 65536` |
| `0x13` | 3 | `MUL`  | `A = (A * imm16) mod 65536` |
| `0x20` | 3 | `STA`  | store `A` as 16-bit little-endian at `addr16` |
| `0x21` | 3 | `LDM`  | `A =` 16-bit little-endian value read at `addr16` |
| `0x30` | 1 | `OUT`  | write `A` to SDATA (decimal + newline) |
| `0xFF` | 1 | `HLT`  | stop execution immediately |

Instruction encoding for the 3-byte forms: byte 0 = opcode, bytes 1–2 =
`imm16`/`addr16` little-endian.

**Execution end conditions (all documented, all deterministic):**

1. `HLT` stops execution immediately.
2. If the program counter reaches the end of the program image (no `HLT`),
   execution stops cleanly.
3. An opcode that is not in the table above is **discarded** — a single byte is
   consumed and execution continues with the next byte.
4. If a 3-byte instruction would extend past the end of the program image (a
   truncated final record), that record is **discarded** and execution stops
   cleanly. The emulator must not crash on such input.

A program with no `OUT` (or an empty image) transmits nothing: the serial log
is an **empty file**.

## 6. Quick-reference numerals

- 64 KiB = `0x10000` bytes = **65536** bytes.
- EPROM base `0x0200` = **512**.
- SDATA `0xF000` = **61440**.

## 7. Bench harness

The emulator host is invoked as:

```
/app/bench/corvid-emu --profile PROFILE.json --rom IMAGE.bin --serial-out OUT.txt
```

It refuses to run without all three arguments and a complete profile; there
are no built-in defaults for any board.
