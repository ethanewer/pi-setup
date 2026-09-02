# elm-yonder : LLVM / binary toolchain

You are given loose per-module LLVM IR files, a small C source, an ELF sample, a
symbolic-execution module, and an SMT-LIB proof-of-work query. Build a small but
complete toolchain. Everything lives in `/app`.

## Provided inputs (read-only)

- `/app/module_a.ll` - LLVM IR defining `add_twice(i32,i32)`.
- `/app/module_b.ll` - LLVM IR that *declares* `add_twice` and defines `add_one`
  and `call_twice` (a genuine cross-module reference).
- `/app/src/sample.c` - small C program (its `main` calls the cross-module
  functions). Rebuild it yourself with debug metadata.
- `/app/sample.elf` - a sample ELF executable (compiled with `-no-pie`) for you
  to test the ELF parser against.
- `/app/prog.sym` - a symbolic-execution module (JSON, see the grammar below).
- `/app/pow.smt2` - a proof-of-work SMT-LIB query.

The toolchain is used later by an automatic verifier against *hidden* versions of
each input (other IR modules, other ELF binaries, other `.sym` modules, other
SMT-LIB queries). Every deliverable below must therefore be a *general* program,
not a hard-coded answer, and must accept its input via a command-line argument
or stdin.

## Required deliverables (write all five under /app)

### 1. `/app/link.py` (general IR linker) and `/app/all.bc`

`link.py` coalesces any number of per-module LLVM IR files into **one linkable
bitcode module** that resolves cross-module references. Invocation:

```
python3 /app/link.py -o OUT.bc IN1.ll [IN2.ll ...]
```

It must run the system `llvm-link` (or fall back to any `llvm-link-*` tool found
on `PATH`) over the `.ll` inputs and write the combined module to `OUT.bc`. It
must work for any set of IR files, not just the fixtures. Exit non-zero on
failure.

Then BUILD these to produce `/app/all.bc` (the "self-contained assembled IR
module"):

```
clang -g -c -emit-llvm /app/src/sample.c -o /app/sample_dbg.ll   # debug metadata
python3 /app/link.py -o /app/all.bc /app/module_a.ll /app/module_b.ll /app/sample_dbg.ll
```

`/app/all.bc` must therefore (a) contain definitions of `add_twice`, `add_one`,
`call_twice` and `main`, (b) contain **no unresolved** `declare i32 @add_twice`
left over (the cross-module call must be resolved), and (c) carry source-level
**debug metadata** (the `!llvm.dbg.cu` / `!DICompileUnit` records) from the `-g`
rebuild. Do not modify the provided `.ll` fixtures.

### 2. `/app/elf.py` (ELF -> address/word JSON)

Parses an ELF header + section-header table and prints a JSON object mapping
memory addresses to 32-bit words. Invocation:

```
python3 /app/elf.py <path-to-elf>
```

- Reads the ELF *magic*, `EI_CLASS` (32- or 64-bit) and `EI_DATA` (byte order)
  from the fixed ELF header offsets, then the Section Header Table offset, entry
  size and count.
- For every section with `sh_type != SHT_NOBITS` (8) that has `sh_size > 0` and
  whose `sh_offset + sh_size` fits within the file, decode its bytes as a
  sequence of 32-bit words using the ELF's byte order. Each word at file offset
  `sh_offset + 4*k` maps to the *memory address* `sh_addr + 4*k`.
- Print to stdout a single JSON object, keys sorted by address, e.g.
  `{"0x401000": 723421, "0x401004": 1234, ...}`. Keys are lowercase hex strings
  beginning with `0x` with no leading-zero padding; values are unsigned 32-bit
  integers. Do NOT include words beyond the section's `sh_size`, do not include
  NOBITS sections, and do not read past the end of the file.

This must work for both ELF32 and ELF64, and both little- and big-endian files.

### 3. `/app/sym.py` (symbolic engine producing branch-covering cases)

Runs a small symbolic engine over a `.sym` module so that **every branch
acquires concrete input cases covering both outcomes**. Invocation:

```
python3 /app/sym.py <module.sym>
```

A `.sym` module is JSON:

```
{ "vars": ["x","y"], "range": [-6,6],
  "gates": [ {"id":"g1","cond":"x + y >= 1"}, ... ] }
```

`cond` is a single comparison `EXPR CMP EXPR` where `CMP` is one of
`< <= > >= == !=` (in that operator order, tested greedily left-to-right as
`<=`,`>=`,`==`,`!=` before `<`,`>`), and `EXPR` is an integer expression over the
declared variables and integer literals using `+ - *` (with `*` binding tighter
than `+ -`, left-associative) and parentheses; no division, no unary minus
(negative integers appear only as literals).

For **each gate and each of its two outcomes (true / false)**, find one concrete
integer assignment to every variable (each value within `[lo,hi]`) that makes
that gate's condition evaluate to that outcome. Print to stdout:

```
{ "vars": ["x","y"], "range": [-6,6],
  "coverage": [
     {"gate":"g1","truth":true,"input":[int,int]},
     {"gate":"g1","truth":false,"input":[int,int]},
     ... one entry per (gate,outcome) that is feasible ...
  ] }
```

Every produced `input` must actually make the gate's condition evaluate to
`truth` (the verifier re-evaluates). If an outcome is infeasible within the
range it may be omitted. You may use the installed `z3` Python bindings or a
search of your own, but the engine must be general (it must read the module
from the file argument, not hard-code `prog.sym`).

### 4. `/app/solver.py` (SMT-LIB verdict on stdin)

Reads a complete quantifier-free bit-vector SMT-LIB script from **stdin**, solves
it, prints the verdict (`sat` / `unsat` / `unknown`) to stdout, and exits with
status 0. Invocation: `python3 /app/solver.py < query.smt2`. Use the installed
`z3` (either via its CLI with `-in -smt2` or the Python bindings). It must accept
piped stdin, must not hang on the given queries, and must return the real
verdict (some hidden queries are unsatisfiable). Exit code 0 on success.

## Rules

- Work only in `/app`. Write `/app/link.py`, `/app/all.bc`, `/app/elf.py`,
  `/app/sym.py`, `/app/solver.py`.
- Do not modify `/app/module_a.ll`, `/app/module_b.ll`, `/app/src/sample.c` or
  the shipped sample fixtures.
- The verifier runs each deliverable on hidden inputs with a fresh copy of the
  container, so the programs must be self-contained (no writes to paths other
  than the output you are told to write) and deterministic on any valid module /
  ELF / `.sym` / SMT-LIB input.
