# Output contract (modes) — /app/vm.js CLI

`vm.js` must accept the same CLI and produce byte-identical output/behavior as
`tools/ref.py` in all three modes:

```
node vm.js <elf>            # plain mode
node vm.js <elf> --trace
node vm.js <elf> --snapshot
node vm.js <elf> --stdin FILE     # any mode; bytes of FILE are read(0,...) input
```

## Plain mode (default)
Run the guest. Write the guest stdout (write(1, ...) bytes) to the process
stdout, exactly as produced. Exit with the guest's exit status (`exit(code)`
status; `139` for segv; `132` for illegal opcode; `1` for step-limit).

## --trace mode
Print one line per executed instruction plus syscall/trap bookkeeping, in this
exact format, then a final status line. Exit with the guest status.

For every executed instruction:

```
pc=0x<8-hex-lower> op=<name>
```

`<name>` is the mnemonic of the executed instruction (`addiu`, `beq`, ...;
`syscall` for the syscall instruction). `<8-hex-lower>` is the address of the
instruction itself (8 hex digits, lowercase, zero-padded).

Additional lines (only these three syscalls produce extra lines):

```
syscall write fd=1 addr=0x<8-hex> count=<n>
syscall read fd=0 addr=0x<8-hex> count=<n> done=<k>
syscall exit code=<c>
```

The final line is always:

```
exit status=<n>
```

On a trap, the line for the faulting instruction is **not** printed; instead

```
vm trap: segv
vm trap: illegal-opcode pc=0x<8-hex> op=<o>
vm trap: step-limit
```

is printed (immediately before the `exit status=...` line).

## --snapshot mode
Print a single JSON object to stdout and exit 0:

```json
{"pc":<u32>,"regs":[<u32 r0>,<u32 r1>,...<u32 r31>]}
```

No spaces; `pc` is the value of the program counter at the moment execution
stopped (the address after the final executed instruction; for an `exit(code)`
that is the address of the instruction following the `syscall`); `regs` lists
all 32 registers in register-number order as unsigned decimal integers.

## Deterministic environments
- Memory and registers start in the documented initial state; the process is
  fully deterministic given the ELF and `--stdin` contents.
- Guest stdout in plain mode and traces in `--trace` mode are compared
  byte-for-byte, so keep output free of extra diagnostics in these modes
  (debug prints belong to your console, not stdout).