# elm-yonder : LLVM / binary toolchain

You are given loose per-module LLVM IR files, a small C source, an ELF sample, a
symbolic-execution module and an SMT-LIB proof-of-work query. Build a small but
complete toolchain. Everything lives in `/app`.

An automatic verifier will later run your four programs **again on hidden
versions of every input** (other IR modules, other ELF binaries, another `.sym`
module, other SMT-LIB queries). Every deliverable must therefore be a *general*
program that reads its input from a command-line argument or stdin — never a
hard-coded answer for the shipped fixtures.

## Provided inputs (read-only, do not modify)

- `/app/module_a.ll` – LLVM IR defining `add_twice(i32,i32)`.
- `/app/module_b.ll` – LLVM IR that *declares* `add_twice` and defines `add_one`
  and `call_twice` (a genuine cross-module reference).
- `/app/src/sample.c` – small C program whose `main` calls the cross-module
  functions. Rebuild it yourself **with debug metadata**.
- `/app/sample.elf` – a sample ELF executable (built with `-no-pie` so section
  addresses are real) for you to test the ELF parser against.
- `/app/prog.sym` – a symbolic-execution module (JSON, grammar below).
- `/app/pow.smt2` – a proof-of-work SMT-LIB query.

## Required deliverables (write all five under /app)

### 1. `/app/link.py` (general IR linker) + `/app/all.bc`

`link.py` coalesces any number of per-module LLVM IR files into **one linkable
bitcode module** that resolves cross-module references. Invocation:

```
python3 /app/link.py -o OUT.bc IN1.ll [IN2.ll ...]
```

It must invoke the system `llvm-link` tool (try the versioned names
`llvm-link-18`, `llvm-link-17`, … then plain `llvm-link`) over the `.ll` inputs
and write the combined module to `OUT.bc`. It must work for any set of IR files,
not just the fixtures. Exit non-zero on failure.

Then BUILT these to produce `/app/all.bc`:

```
clang -g -c -emit-llvm /app/src/sample.c -o /app/sample_dbg.ll
python3 /app/link.py -o /app/all.bc /app/module_a.ll /app/module_b.ll /app/sample_dbg.ll
```

`/app/all.bc` must therefore (a) contain definitions of `add_twice`, `add_one`,
`call_twice` and `main`, (b) contain **no leftover unresolved**
`declare i32 @add_twice` (the cross-module call must be resolved), and (c) carry
source-level **debug metadata** (`!DICompileUnit` / `!llvm.dbg` records) from the
`-g` rebuild. Do not modify the shipped `.ll`/`.c` fixtures.

### 2. `/app/elf.py` (ELF → address/word JSON)

Parses an ELF header + section-header table and prints a JSON object mapping
memory addresses to 32-bit words. Invocation: `python3 /app/elf.py <path>`.

- Read the ELF *magic* (`\x7fELF`), `EI_CLASS` (byte 4: 1 = ELF32, 2 = ELF64) and
  `EI_DATA` (byte 5: 1 = little-endian, 2 = big-endian), then the Section Header
  Table offset / entry-size / count from the fixed ELF header offsets
  (ELF32: `e_shoff`@0x20, `e_shentsize`@0x2E, `e_shnum`@0x30; ELF64: `e_shoff`@0x28,
  `e_shentsize`@0x3A, `e_shnum`@0x3C).
- For every section header with `sh_type != 8` (SHT_NOBITS) that has `sh_size > 0`
  and whose `sh_offset + sh_size` fits within the file, decode its bytes as a
  sequence of 32-bit words using the ELF's byte order. The word at file offset
  `sh_offset + 4*k` maps to memory address `sh_addr + 4*k`. Section-header field
  offsets (ELF64: `sh_addr`@0x10, `sh_offset`@0x18, `sh_size`@0x20; ELF32:
  `sh_addr`@0x0C, `sh_offset`@0x10, `sh_size`@0x14).
- Print to stdout one JSON object, keys sorted by address, e.g.
  `{"0x401000": 723421, "0x401004": 1234}`. Keys are lowercase hex strings
  beginning with `0x`, **no** leading-zero padding; values are **unsigned 32-bit
  integers**.
- Edge cases: a section with `sh_size` not a multiple of 4 (drop the trailing
  bytes), a truncated/malformed file where a section header does not fit or a
  section extends past EOF (skip that section), and a file with **no** readable
  sections must yield `{}` — never crash. Your program must handle both ELF32 and
  ELF64 and both byte orders. Do not print trailing garbage or section names.

### 3. `/app/sym.py` (symbolic engine → branch-covering cases)

Runs a small symbolic engine over a `.sym` module so that **every branch
acquires concrete input cases covering both outcomes**. Invocation:
`python3 /app/sym.py <module.sym>`.

A `.sym` module is JSON:

```
{ "vars": ["x","y"], "range": [-6,6],
  "gates": [ {"id":"g1","cond":"x + y >= 1"}, ... ] }
```

`cond` is exactly one comparison `EXPR CMP EXPR`. `CMP` is one of
`<= >= == != < >` (match two-character operators before single-character `< >`).
`EXPR` is an integer expression over the declared variables and integer literals
using `+ - *` with `*` binding tighter than `+ -` (left-associative) plus
parentheses; there is **no** division and **no** unary minus (negative values
only appear as integer literals).

For **each gate and each of its two outcomes (true / false)**, find one concrete
integer assignment to *every* variable (each value inside `[lo,hi]`) that makes
that gate's condition evaluate to that outcome. Print to stdout:

```
{ "vars": ["x","y"], "range": [-6,6],
  "coverage": [
     {"gate":"g1","truth":true,"input":[1,0]},
     {"gate":"g1","truth":false,"input":[-6,0]}, ... ] }
```

Every produced `input` must actually satisfy `cond(input) == truth` (the verifier
re-evaluates). The engine must be general — read the module from the file
argument, never hard-code `prog.sym`. You may use the installed `z3` Python
bindings or your own search (including a bounded brute-force within the range);
if an outcome is infeasible within the range you may omit it, but for the given
inputs every outcome is feasible.

### 4. `/app/solver.py` (SMT-LIB verdict on stdin)

Reads a complete quantifier-free bit-vector SMT-LIB script from **stdin**, solves
it, prints the verdict line(s) (`sat` / `unsat` / `unknown`) to stdout and exits
with status 0. Invocation: `python3 /app/solver.py < query.smt2`. Use the
installed `z3` (CLI `z3 -in -smt2` with the piped stdin, or the Python
bindings). It must accept piped stdin, must not hang, and must return the *real*
verdict — **some** hidden queries are unsatisfiable, so never hard-code `sat`.

## Rules

- Work only in `/app`. Write `/app/link.py`, `/app/all.bc`, `/app/elf.py`,
  `/app/sym.py`, `/app/solver.py`.
- Do not modify `/app/module_a.ll`, `/app/module_b.ll`, `/app/src/sample.c` or the
  sample fixtures.
- Programs must be self-contained and deterministic on any valid module / ELF /
  `.sym` / SMT-LIB input, since the verifier runs them in a fresh container on
  hidden inputs.
