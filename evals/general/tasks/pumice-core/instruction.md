# Pumice-core: resurrect big-endian MIPS firmware in a JavaScript VM

A pile of legacy boards runs **big-endian MIPS32** firmware images. You must
write a runnable **ELF interpreter in JavaScript** (pure Node, no npm packages)
that loads such an image, decodes the instruction stream, and emulates the
CPU's registers and memory faithfully — including **branch delay slots**.

Everything is under `/app`:

- `/app/samples/boot.elf` — a visible big-endian MIPS32 ELF program.
- `/app/tools/mipsasm.py` — an assembler for the exact instruction subset
  documented below (run `python3 /app/tools/mipsasm.py prog.s prog.elf`) that
  produced every sample and grading image; use it to build your own test
  programs. Its source doubles as an encoding reference.
- Node.js (v22) is installed as `node`.

## Deliverables

1. `/app/vm.js` — the interpreter. Invocation:
   ```
   node /app/vm.js <elf-file>
   ```
   The guest's stdout bytes go to your stdout; diagnostics go to stderr; the
   interpreter's exit status is the guest's exit status (or an error code,
   below). It must run from any working directory and accept any ELF that
   follows the layout rules, not just the visible sample.

2. `/app/sample_out.txt` — the exact stdout of running
   `node /app/vm.js /app/samples/boot.elf` (redirect, do not hand-write).

## ELF layout the VM must accept

- ELFCLASS32 (`ei_class`=1), **big-endian** (`ei_data`=2), `e_machine`=8
  (EM_MIPS). Anything else: print a diagnostic to stderr and exit `1`.
- One or more `PT_LOAD` program headers (32-byte entries at `e_phoff`,
  `e_phentsize`, `e_phnum` in the ELF header): for each, copy `p_filesz` bytes
  from file offset `p_offset` to guest address `p_vaddr` and zero-fill up to
  `p_memsz`. Typical images load text at `0x00100000` and data at `0x00200000`;
  `e_entry` is where execution starts.
- Flat guest memory of **64 MiB**: valid addresses are `0x00000000..0x03FFFFFF`.
- `$sp` is initialized to `0x03FFF000` (stack grows down); all other registers
  start at 0. Register `$0` is hardwired to zero.

## Instruction set (decode and execute exactly)

R-type (opcode 0, decode by `funct`): `sll`(0x00) `srl`(0x02) `sra`(0x03)
`sllv`(0x04) `srlv`(0x06) `srav`(0x07) `jr`(0x08) `jalr`(0x09) `syscall`(0x0c)
`mfhi`(0x10) `mthi`(0x11) `mflo`(0x12) `mtlo`(0x13) `mult`(0x18)
`multu`(0x19) `div`(0x1a) `divu`(0x1b) `add`(0x20) `addu`(0x21) `sub`(0x22)
`subu`(0x23) `and`(0x24) `or`(0x25) `xor`(0x26) `nor`(0x27) `slt`(0x2a)
`sltu`(0x2b).

REGIMM (opcode 1): `bltz` (rt=0), `bgez` (rt=1), `bltzal` (rt=16),
`bgezal` (rt=17). J-type: `j`(2), `jal`(3). I-type opcodes: `beq`(4)
`bne`(5) `blez`(6) `bgtz`(7) `addi`(8) `addiu`(9) `slti`(0xa) `sltiu`(0xb)
`andi`(0xc) `ori`(0xd) `xori`(0xe) `lui`(0xf) `lb`(0x20) `lh`(0x21) `lw`(0x23)
`lbu`(0x24) `lhu`(0x25) `sb`(0x28) `sh`(0x29) `sw`(0x2b).

Semantics — standard MIPS32:

- **Branch delay slots are simulated.** The instruction immediately after a
  branch or jump *always executes* before control transfers. Branch targets
  are `addr_of_delay_slot + (sign_extended_imm << 2)`. `jal`/`jalr`/`bltzal`/
  `bgezal` write the return address `pc + 8` (skipping the delay slot) into
  `$ra` (or the `jalr` register). `j`/`jal` targets use the high 4 bits of the
  delay-slot address with the 26-bit index shifted left 2.
- `mult`/`multu` write the 64-bit signed/unsigned product into `hi`/`lo`;
  `div` truncates toward zero (`lo`=quotient, `hi`=remainder, C semantics);
  `divu` is unsigned. Division by zero leaves `hi`/`lo` unchanged.
- `add`/`addi`/`sub` never trap — they wrap exactly like `addu`/`addiu`/`subu`.
- Variable shifts use `rs & 31`. `addi/addiu/slti/lb/lh` sign-extend;
  `andi/ori/xori` and `lbu/lhu` zero-extend; `lui` writes `imm << 16`;
  `sltiu` sign-extends the immediate but compares unsigned.
- `lw/sw` require 4-byte and `lh/lhu/sh` 2-byte alignment.
- `syscall` dispatches on `$v0` (see ABI below).

## Guest syscall ABI

- `$v0 == 343` — `print_int`: write `$a0` as a **signed decimal** followed by a
  newline to stdout.
- `$v0 == 344` — `print_string`: write `$a1` raw guest bytes starting at guest
  address `$a0` to stdout (no added newline).
- `$v0 == 93` — `exit(status=$a0)`: terminate immediately with exit status
  `$a0 & 0xFF`.
- any other `$v0` — print a diagnostic to stderr and exit `8`.

## Exit / error convention

- guest `exit(0)` → status `0`; guest `exit(N)` → status `N & 0xFF`.
- unsupported instruction (any opcode/funct/REGIMM `rt` outside the lists) →
  diagnostic to stderr, exit `2`.
- guest memory access or instruction fetch outside `0x00000000..0x03FFFFFF`,
  or an unaligned word/half access → diagnostic to stderr, exit `7`.
- unknown syscall → diagnostic to stderr, exit `8`.
- more than 50,000,000 instructions executed (infinite loop guard) →
  diagnostic to stderr, exit `9`.

## Grading

The verifier re-runs `/app/vm.js` unchanged on the visible sample and on
**hidden** big-endian MIPS32 images that exercise: arithmetic with
`mult`/`multu`/`div`/`divu`/`hi`/`lo`, variable shifts and compares, **live
branch/jump delay slots**, byte/halfword loads and stores with sign/zero
extension, recursion through the stack (`jal`/`jr`/`sw`/`lw`), a program with
an unsupported opcode, and a program that touches memory outside the guest
range. For each, stdout must match byte-for-byte and the exit status must be
exact. If you special-case the visible sample's bytes, the hidden programs
will fail.

## Constraints

- Pure Node core APIs only (`fs`, `process`, `Buffer` are fine); no npm
  packages, no network access, no child processes, no `eval` of the guest.
- Do not modify `/app/samples/` or `/app/tools/`.
- Keep the exact deliverable paths; do not add banners to stdout.
