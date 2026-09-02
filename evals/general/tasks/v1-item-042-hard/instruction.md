# Implement a MIPS32 subset emulator in Node.js (hard)

`/app` contains a MIPS software-emulation workbench. Your job is to
**implement `/app/vm.js`**, a Node.js emulator of a documented MIPS32 subset
(registers, memory, instruction set, ELF loading, syscalls, **fault
handling**) that is behaviorally identical to the supplied reference
implementation. You will build it **incrementally from traces**, using
**differential testing against the reference** to discover and fix low-level
state mismatches. The hidden verification is adversarial: it includes
function calls (**jal/jalr** + stack + `restore $31`), **read(0,...)** from
stdin, **traps** (an out-of-memory load must fault), and several different
inputs — so correctness must be general, not sample-specific.

## What is in /app

- `tools/isa.md` — the **authoritative specification**: registers, memory
  model, ELF32 loading rules, initial state, exact instruction set with
  encodings and semantics, syscall numbers, and trap behavior (`segv`,
  `illegal-opcode`, `step-limit` statuses). Read it fully.
- `tools/trace-format.md` — the exact output contract for `vm.js` (plain /
  `--trace` / `--snapshot` modes). Trace and snapshot output are compared
  **byte-for-byte**, including the `vm trap: ...` and `exit status=...`
  lines.
- `tools/ref.py` — the **reference implementation** (Python).
- `tools/asm.py` — assembler for the subset.
- `tools/difftest.sh` — differential harness over every sample (`fact6.elf`
  and `segv.elf`), in all three modes.
- `samples/fact6.elf` — computes `6! = 720` via a **recursive function** on
  the stack (test your `jal`/`jalr`, `lw`/`sw`, `$ra` save/restore).
- `samples/fact6.s`, `samples/fact6.expected.trace`,
  `samples/fact6.expected.snapshot.json`, `samples/segv.elf`,
  `samples/segv.s`, `samples/segv.expected.trace` — sources + reference
  outputs (note segv's expected output is a `vm trap: segv` + status 139).

## What to build

`/app/vm.js`, invoked like the reference:

```
node vm.js <elf> [--trace] [--snapshot] [--stdin FILE]
```

Must match `tools/ref.py` in all three modes, including stdout bytes, exit
statuses, `--trace` lines (`pc=0x... op=...`, syscall lines, trap lines, and
`exit status=N`), and the exact `--snapshot` JSON.

## Recommended workflow

1. Read `tools/isa.md` and `tools/trace-format.md`.
2. Scaffold: register file (`$zero` read-only), 4 MiB memory, ELF32 loader,
   fetch/decode/execute loop, syscalls `write(1)`, `read(0)`, `exit`.
3. Run `bash tools/difftest.sh`; use the printed per-line diffs from
   `--trace`/`--snapshot` to drive the implementation: start with
   arithmetic, then branches/jumps (`beq`, `j`, `jal`, `jr`, `blez`),
   then memory ops and `mult`/`div`/`mflo`/`mfhi`.
4. Verify trap semantics: `node vm.js samples/segv.elf --trace` must end in
   `vm trap: segv` + `exit status=139`.
5. Iterate until `difftest.sh` reports `ALL SAMPLES MATCH`. The hidden
   programs exercise the same feature set with different inputs and through
   stdin; make sure `--stdin` is honored.

## Success criteria
- `/app/vm.js` matches `tools/ref.py` byte-for-byte on `samples/fact6.elf`
  and `samples/segv.elf` in all three modes,
- it runs correctly on unseen programs the verifier assembles (factorial via
  a recursive function, with inputs `6` and `9` through stdin; a program that
  deliberately triggers a `segv`),
- it prints nothing extra to stdout in the three modes.