# Emulator contract — MIPS32 subset, ELF loading, syscalls

This is the authoritative specification for `/app/vm.js` (the program you must
implement). `tools/ref.py` is a reference implementation of exactly this
contract; use it for differential testing (see `tools/difftest.sh`).

## Registers
32 GPRs, each a 32-bit unsigned value. `$zero` (r0) is hard-wired to 0 —
writes to r0 are ignored. Notational names: `r1=$at, r2=$v0, r3=$v1,
r4..r7=$a0..$a3, r8..$t7, r16..r23=$s0..$s7, r24=$t8, r25=$t9, r28=$gp,
r29=$sp, r30=$fp, r31=$ra`.

## Memory model
- 4 MiB of byte-addressable memory (addresses 0x00000000 .. 0x003FFFFF).
- Data is **big-endian**; word loads/stores must be at fully in-range
  addresses. Any access with an address `< 0` or `>= 4 MiB` (after unsigned
  add of base register + sign-extended offset) is a `segv` trap (below).
- There is **no alignment restriction** beyond the range check (the subset
  does not model unaligned-word traps). `lwl`/`lwr`/`swl` behave exactly like
  `lw`, `lw`, `sw` respectively (alignment-merge is not modeled).

## ELF loading (flat ELF32, big-endian)
`vm.js <elf>` accepts a flat ELF32 produced by `tools/asm.py`:

- `e_ident`: `7f 'E' 'L' 'F'`; EI_CLASS (byte 4) = 1 (ELF32); EI_DATA (byte 5)
  = 2 (big-endian). Anything else is a hard load error (print the message and
  exit nonzero — but none of the shipped programs require this path).
- `e_entry` (bytes 24..27) is the initial `pc`.
- Program header table at `e_phoff` (bytes 28..31), `e_phentsize`
  (bytes 42..43), `e_phnum` (bytes 44..45). For each `PT_LOAD` (p_type 1)
  entry: copy `p_filesz` bytes from file offset `p_offset` to address
  `p_vaddr`, then zero-fill `p_memsz - p_filesz` bytes after it.
- Load segments may overlap only conceptually; programs here have one
  `PT_LOAD` with `p_vaddr = 0x00100000`.

## Initial state
- `pc = e_entry`; `$sp = 0x00200000`; every other register `0`.
- No branch-delay slots: the instruction following a branch/jump/`jr` is
  **not** executed speculatively. Control instructions compute their next pc
  directly.

## Instruction set (encodings: opcode = bits 31..26)
All encodings are standard MIPS32 (big-endian word). Fields:
rs = bits 25..21, rt = bits 20..16, rd = bits 15..11, shamt = bits 10..6,
funct = bits 5..0, imm = bits 15..0 (sign-extended for signed ops).

R-type (opcode 0):

| funct | mnemonic | semantics |
| --- | --- | --- |
| 0x00 | `sll rd, rt, shamt` | rd = rt << shamt |
| 0x02 | `srl rd, rt, shamt` | rd = rt >> shamt (logical) |
| 0x03 | `sra rd, rt, shamt` | rd = rt >> shamt (arithmetic) |
| 0x04 | `sllv rd, rt, rs` | rd = rt << (rs & 31) |
| 0x06 | `srlv rd, rt, rs` | rd = rt >> (rs & 31) (logical) |
| 0x07 | `srav rd, rt, rs` | rd = rt >> (rs & 31) (arithmetic) |
| 0x08 | `jr rs` | pc = rs |
| 0x09 | `jalr rs` | ra = next pc; pc = rs |
| 0x10 | `mfhi rd` | rd = HI |
| 0x11 | `mthi rs` | HI = rs |
| 0x12 | `mflo rd` | rd = LO |
| 0x13 | `mtlo rs` | LO = rs |
| 0x0c | `syscall` | see Syscalls |
| 0x20 | `add rd, rs, rt` | rd = rs + rt (signed, wrap) |
| 0x21 | `addu rd, rs, rt` | rd = rs + rt (wrap) |
| 0x22 | `sub rd, rs, rt` | rd = rs - rt (signed, wrap) |
| 0x23 | `subu rd, rs, rt` | rd = rs - rt (wrap) |
| 0x24 | `and rd, rs, rt` | rd = rs & rt |
| 0x25 | `or rd, rs, rt` | rd = rs \| rt |
| 0x26 | `xor rd, rs, rt` | rd = rs ^ rt |
| 0x27 | `nor rd, rs, rt` | rd = ~(rs \| rt) |
| 0x2a | `slt rd, rs, rt` | rd = 1 if rs < rt (signed) else 0 |
| 0x2b | `sltu rd, rs, rt` | rd = 1 if rs < rt (unsigned) else 0 |

special2 (opcode 28):

| funct | mnemonic | semantics |
| --- | --- | --- |
| 0x00 | `mult rs, rt` | LO = rs*rt (signed, low 32 bits), HI = 0 |
| 0x01 | `multu rs, rt` | LO = rs*rt (unsigned, low 32 bits), HI = 0 |
| 0x02 | `div rs, rt` | if rt != 0: LO = rs/rt truncated toward zero, HI = rs%rt; else LO = HI = 0 |
| 0x03 | `divu rs, rt` | if rt != 0: LO = rs/rt (unsigned floor), HI = rs%rt; else LO = HI = 0 |

REGIMM (opcode 1, sub-opcode in rt field):

| rt | mnemonic | semantics |
| --- | --- | --- |
| 0x00 | `bltz rs, imm` | if rs < 0: pc = next + (imm << 2) |
| 0x01 | `bgez rs, imm` | if rs >= 0: pc = next + (imm << 2) |
| 0x10 | `bltzal rs, imm` | ra = next; if rs < 0: pc = next + (imm << 2) |
| 0x11 | `bgezal rs, imm` | ra = next; if rs >= 0: pc = next + (imm << 2) |

Branches (opcode: beq 0x04, bne 0x05, blez 0x06, bgtz 0x07): target = next +
(imm << 2) when the condition holds, where imm is sign-extended.

I-type:

| opcode | mnemonic | semantics |
| --- | --- | --- |
| 0x08 | `addi rt, rs, imm` | rt = rs + imm (sign-extended, wrap) |
| 0x09 | `addiu rt, rs, imm` | rt = rs + imm (sign-extended, wrap) |
| 0x0a | `slti rt, rs, imm` | rt = 1 if rs < imm (signed) else 0 |
| 0x0b | `sltiu rt, rs, imm` | rt = 1 if rs < imm (zero-extended) else 0 |
| 0x0c | `andi rt, rs, imm` | rt = rs & imm (zero-extended) |
| 0x0d | `ori rt, rs, imm` | rt = rs \| imm (zero-extended) |
| 0x0e | `xori rt, rs, imm` | rt = rs ^ imm (zero-extended) |
| 0x0f | `lui rt, imm` | rt = imm << 16 |

Jumps (opcode: j 0x02, jal 0x03): target = (next & 0xF0000000) | ((bits
25..0 of the word) << 2). `jal` also sets ra = next.

Memory (base register + sign-extended offset):

| opcode | mnemonic | semantics |
| --- | --- | --- |
| 0x20 | `lb rt, off($rs)` | load byte, sign-extend |
| 0x21 | `lh rt, off($rs)` | load halfword, sign-extend |
| 0x23 | `lw rt, off($rs)` | load word |
| 0x24 | `lbu rt, off($rs)` | load byte, zero-extend |
| 0x25 | `lhu rt, off($rs)` | load halfword, zero-extend |
| 0x28 | `sb rt, off($rs)` | store byte |
| 0x29 | `sh rt, off($rs)` | store halfword |
| 0x2b | `sw rt, off($rs)` | store word |
| (0x22 lwl, 0x26 lwr, 0x2a swl — behave as lw/lw/sw) | | |

## Syscalls
`syscall` dispatches on `$v0`; arguments in `$a0..$a2` (Linux o32 numbers):

- `4001 exit(code)`: stop execution; the process (plain/trace mode) exits with
  `code` as its status.
- `4004 write(fd, addr, count)`: if fd == 1, emit the `count` bytes at
  `addr` to the guest stdout and set `$v0 = count`; otherwise emit nothing and
  set `$v0 = 0`.
- `4003 read(fd, addr, count)`: if fd == 0, copy up to `count` bytes from the
  supplied stdin into memory at `addr`, set `$v0 = bytes copied` (0 at EOF);
  otherwise `$v0 = 0`.
- Any other number: set `$v0 = 0xFFFFFFFF` and continue.

## Traps (fault handling)
Execution stops and the status word becomes:

- out-of-range memory access (read or write): **139** (`segv`)
- unknown opcode / funct / REGIMM / special2: **132** (`illegal-opcode`)
- more than 1,000,000 steps executed: **1** (`step-limit`)

See `tools/trace-format.md` for the exact console output in each mode.

## Assembler (`tools/asm.py`)
`python3 tools/asm.py src.s -o out.elf` — subset syntax used by the sample
programs (also describes registers and pseudo-ops: `nop`, `li`, `la`,
`move`; data directives `.set`, `.word`, `.asciiz`, `.space`). The shipped
programs only use the instructions above plus pseudo-ops.