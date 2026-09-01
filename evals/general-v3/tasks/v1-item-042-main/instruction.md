# Implement a MIPS32 subset emulator in Node.js

`/app` contains a small MIPS software-emulation workbench. Your job is to
**implement `/app/vm.js`**, a Node.js emulator of a documented MIPS32 subset
(registers, memory, instruction set, ELF loading, syscalls, traps), that is
behaviorally identical to the supplied reference implementation. You will
build it **incrementally from traces**, using **differential testing against
the reference** to find and fix low-level state mismatches.

## What is in /app

- `tools/isa.md` — the **authoritative specification**: registers, memory
  model, ELF32 loading rules, initial state, exact instruction set with
  encodings and semantics, syscall numbers, and trap behavior. Read it fully.
- `tools/trace-format.md` — the exact output contract for `vm.js` (the three
  CLI modes). Note that `--trace` and `--snapshot` output are compared
  **byte-for-byte**.
- `tools/ref.py` — the **reference implementation** (Python). Use it as
  ground truth for differential testing.
- `tools/asm.py` — assembler for the subset; builds the flat ELF32 binaries.
- `tools/difftest.sh` — runs both implementations over every sample program
  in all three modes and diffs them.
- `samples/sum10.elf` — sample program (computes 55 and prints it).
- `samples/sum10.s`, `samples/sum10.expected.trace`,
  `samples/sum10.expected.snapshot.json` — source and reference outputs.

## What to build

`/app/vm.js` — the Node.js emulator, invoked like the reference:

```
node vm.js <elf> [--trace] [--snapshot] [--stdin FILE]
```

It must match `tools/ref.py` semantics and output exactly in all three modes
(plain, `--trace`, `--snapshot`), including process exit status (guest
`exit(code)` status, 139 for segv, 132 for illegal opcode). The only "guest
devices" are the o32 syscalls: `4004 write(1,...)` to stdout, `4003
read(0,...)` from `--stdin`, `4001 exit(code)`.

## Recommended workflow (incremental)

1. Read `tools/isa.md` and `tools/trace-format.md` before writing code.
2. Implement the scaffolding: register file (read/write with `$zero` rule),
   4 MiB byte-addressable memory, ELF loader, fetch/decode/execute loop.
3. Implement `addiu`, `lui`/`ori` (the `li` pseudo emits these),
   `syscall` write/exit. Test: `node vm.js samples/sum10.elf` prints `55`.
4. Implement the remaining arithmetic/logic, branches/jumps, memory
   loads/stores, then run `bash tools/difftest.sh` and use its per-line
   diffs to drive fixes. Pay attention to signed/unsigned semantics,
   sign-extended immediates, branch target math, and the snapshot of
   registers at halt (`$sp` moves, so don't assume final values).
5. Keep iterating until `difftest.sh` reports `ALL SAMPLES MATCH` in all
   three modes. The hidden verification runs the same checks plus an
   unknown program it assembles with `tools/asm.py`, so make sure your
   implementation is not special-cased to the sample.

## Success criteria
- `/app/vm.js` exists and matches `tools/ref.py` on `samples/*.elf` in plain,
  `--trace`, and `--snapshot` modes (byte-identical output; identical exit
  statuses),
- it runs correctly on an unseen program the verifier assembles (a
  small `read`+loop+decimal-print program),
- it prints nothing extra to stdout in plain/trace/snapshot modes.