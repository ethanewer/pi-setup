# hollow-dial — resurrect old machines

You are working in a single Linux container for the **hollow-dial** lab. Your job
is to work at the raw machine/binary level: classify the architecture of provided
binary blobs by *reading their headers* (never executing them), build a small but
**faithful MIPS32 ELF interpreter** in C, and build a **self-interpreting Lisp**
evaluator. The lab has three independent parts; do all work under `/app`.

You are graded on the six deliverables:

| Path | What it must be |
|------|-----------------|
| `/app/classify.py` | executable Python 3 program that classifies a binary's architecture/format by inspecting headers |
| `/app/arch_report.json` | JSON produced by running `classify.py` on `/app/samples/sum.pdp11` |
| `/app/mips_interp.c` | C source of a MIPS32 ELF interpreter |
| `/app/mips_out.txt` | output produced by running the interpreter on `/app/samples/greet.mips` |
| `/app/eval.py` | executable Python evaluator for the documented "Liz" Lisp dialect |
| `/app/self_host.txt` | output proving direct execution == one level of self-interpretation |

The verifier will **recompile** `/app/mips_interp.c` and **re-run** `classify.py`
and `eval.py` on new hidden inputs, so they must be generic programs, not
hard-coded to the visible samples.

---

## Part 1 — architecture classifier (`/app/classify.py`)

**Interface.** Exactly:

```
python3 /app/classify.py <file>
```

It must print **one JSON object on stdout** with these keys:
`{"file","format","arch","host_executable","note"}`. It must exit `0` in all of
the cases below (an unreadable file may exit nonzero). Do not print anything to
stdout besides that JSON.

**Classification rules (implement for *every* input):**

1. **ELF** — file begins with the 4 bytes `7f 45 4c 46` (`\x7fELF`):
   - The e_machine field is the 16-bit word at bytes 18–19
     (little-endian if the `ei_data` byte, offset 5, is `1`; big-endian if `2`).
   - `arch` is a fixed short name: `x86`, `x86_64`, `arm`, `aarch64`, `mips`,
     `powerpc`, `powerpc64`, `sparc`, `riscv`, `m68k`, `ia64`, or
     `unknown-elf-machine-N` for any other machine number. You must at least
     handle machines 3 (x86), 62 (x86_64), 40 (arm), 183 (aarch64), 8 (mips),
     20 (powerpc), 21 (powerpc64), 243 (riscv), 18 (sparc), 5 (m68k), 50 (ia64).
   - `format` is `elf-32` (class=1) or `elf-64` (class=2).
   - `host_executable` is `true` **only** for `x86_64` (this host's arch).
   - **Edge:** if the file starts with the ELF magic but is shorter than 20
     bytes (truncated header), still exit `0`, set `format` to `"elf-truncated"`
     and `arch` to `"unknown"` — do *not* crash.
2. **Legacy PDP-11 a.out** — the first 16-bit word (little-endian) is one of the
   a.out magics `0x0107`, `0x0108`, `0x010B`, or `0x00CC`. Then:
   `format` = `"a.out"`, `arch` = `"pdp11"`, `host_executable` = `false`,
   `note` mentions it is machine code for an old 16-bit PDP-11 architecture not
   runnable on this host. Do not require any fixed byte content beyond that
   magic word.
3. **PE stub** — first two bytes `MZ`: `format` = `"pe"`, `arch` = `"x86-family"`,
   `host_executable` = `false`.
4. **Anything else** — `format` = `"unknown"`, `arch` = `"unknown"`,
   `host_executable` = `false`, and (optional) if the blob is ≥8 bytes and more
   than ~90% printable ASCII, set `format` = `"text"`. Never raise an exception.

`/app/arch_report.json` is simply the JSON (in a JSON **file**, i.e. the object
cannot contain a trailing comma) that `classify.py` prints for
`/app/samples/sum.pdp11` — `arch` must be `pdp11`.

---

## Part 2 — MIPS32 ELF interpreter (`/app/mips_interp.c`)

Write a C program that **loads a small 32-bit little-endian MIPS ELF
executable**, emulates its registers and memory, decodes and executes the
instruction stream, and writes the program's output to `stdout`. It must be
compiled with the system `gcc`; the verifier recompiles it itself, so do not
require any out-of-tree library.

**Command.** `/app/mips_interp <elf-file>`. Guest `stdout` becomes the program's
`stdout`.

**ELF layout the interpreter must accept** (this is what every sample and hidden
program uses — support this precisely):

- ELFCLASS32 (`ei_class`=1), little-endian (`ei_data`=1), `e_machine`=8 (`EM_MIPS`).
- A single `PT_LOAD` segment: `p_vaddr=0x00400000`, `p_offset=52+32`;
  `p_filesz = p_memsz` = (code bytes + data bytes). Load `p_filesz` bytes from
  file `p_offset` into guest memory at `p_vaddr`; `e_entry = 0x00400000`.
- The guest has a flat 128 MB address space (`0x00000000..0x07ffffff`).
- `$sp` is initialized to `0x07fff000` (the stack grows down below it).

### Instruction set the interpreter must decode and execute correctly

R-type (opcode 0, decode by `funct`): `sll`(0x00), `srl`(0x02), `sra`(0x03),
`jr`(0x08), `syscall`(0x0c), `addu`(0x21), `subu`(0x23), `and`(0x24), `or`(0x25),
`xor`(0x26), `nor`(0x27), `slt`(0x2a), `sltu`(0x2b).

I-type (by opcode): `addi`(0x08), `addiu`(0x09), `slti`(0x0a), `sltiu`(0x0b),
`andi`(0x0c), `ori`(0x0d), `xori`(0x0e), `lui`(0x0f), `lb`(0x20), `lbu`(0x24),
`lw`(0x23), `lhu`(0x25), `sb`(0x28), `sh`(0x29), `sw`(0x2b), `beq`(0x04),
`bne`(0x05), `blez`(0x06), `bgtz`(0x07), and the `REGIMM` family (opcode 1:
`bltz` rt=0, `bgez` rt=1). J-type: `j`(0x02), `jal`(0x03).

Semantics follow the standard MIPS32 ISA (register 0 is always zero; branches
offset `imm16<<2` added to the *delay-slot-free* next-PC; `lui` writes
`imm16<<16` to `rt`; `andi/ori/xori` zero-extend the immediate while
`addiu/slti` sign-extend it; memory offsets are sign-extended 16-bit). Do **not**
implement a branch delay slot — treat branches as taking effect immediately on
the instruction after the branch.

### Guest syscall ABI

On `syscall`, dispatch on `$v0`:

- `$v0 == 4004` — `write(fd=$a0, buf=$a1, count=$a2)`. If `fd==1` copy `count`
  guest bytes starting at `$a1` to the program's `stdout`; if `fd==2` to stderr.
  On success set `$v0` to the count written.
- `$v0 == 4001` — `exit(status=$a0)`. Interpret the `exit` and terminate the
  interpreter immediately with that status.
- any other `$v0` — print `mips: unknown syscall` to **stderr** and exit `4`.

### Exit / error convention (the hidden "malformed" case needs this)

- guest `exit(0)` / interpreter finishing → exit code `0`;
- guest `exit(N)` → interpreter exits `N`;
- **unsupported instruction** (any opcode/funct outside the list above) → print
  a line to **stderr** and exit `3`;
- any guest memory access (including instruction fetch) outside
  `0x00000000..0x07ffffff` → print to stderr and exit `5`;
- the interpreter should also guard against `>200,000,000` instructions (an
  infinite loop) → print to stderr and exit `6`.

Hidden programs exercise several distinct programs (arithmetic + byte stores to
the stack, reading a data string + a counted branch loop, an immediate exit with
no output, a `lb` loop) and one program containing an **unsupported opcode** that
your interpreter must reject. If you special-case the visible sample's bytes,
the hidden programs will fail.

To build the deliverable and produce `mips_out.txt`:

```
gcc -O2 -o /app/mips_interp /app/mips_interp.c
/app/mips_interp /app/samples/greet.mips > /app/mips_out.txt
```

`/app/mips_out.txt` must equal exactly what `/app/samples/greet.mips` prints
(do not hand-write it).

---

## Part 3 — the "Liz" evaluator (`/app/eval.py`)

Implement a runnable interpreter for the tiny Scheme-like dialect **Liz**, in
Python, at `/app/eval.py`:

```
python3 /app/eval.py <program.lsp>
```
Output goes only to `stdout` via the `print` builtin; errors go to `stderr` with
exit code 1.

### Values
Integers (arbitrarily big, negative allowed), symbols (identifiers), booleans
`#t`/`#f`, the empty list `()`, and **pairs** building proper lists
`(a b c ...)` — dotted pairs like `(7 . 9)` are also possible.

### Program syntax & parsing
- Comments: `;` to end of line.
- Atoms: `42`, `-3`, `#t`, `#f`, `symbol-name`.
- A single apostrophe is sugar: `'x` ≡ `(quote x)`; `'()` is the empty list.
- A program is zero or more top-level forms evaluated left-to-right.

### Evaluation rules
- Self-evaluating: numbers and booleans and `()`.
- A **symbol** looks up its value in the environment (unbound symbols denote
  themselves, matching the meta-circular path).
- Special forms (first element):
  - `(quote X)` → `X` unevaluated.
  - `(if C T E)` — evaluate `C`; if `C` is `#f` evaluate `E`, else evaluate `T`.
  - `(define name (lambda (params...) body...))` and the shorthand
    `(define (name p1 p2 ...) body...)` → bind `name` in the current (top-level)
    environment. The value is the just-defined closure (so recursion across
    top-level definitions works).
  - `(lambda (p1 p2 ...) body...)` → a closure capturing the current env.
  - `(begin e1 e2 ...)` → sequential; value = last.
- Anything else evaluates the operator and each operand left-to-right and applies.

### Application
- A closure → bind its params to the (already evaluated) args in a child lexical
  env and evaluate its body; lexical scoping and recursion must work.
- A primitive name → call the primitive.

### Builtins (fixed arity)
Binary numbers: `+ - * quotient remainder = < > <= >=` (e.g. `(+ 3 4)`).
`quotient`/`remainder` error on a zero divisor. Forward/return booleans.
List: `cons car cdr null? pair?` `cons` of two lists builds a proper
list; `(cons 7 9)` is a dotted pair whose `car` is `7` and `cdr` is `9`.
Predicates returned `#t`/`#f`: `null? pair? symbol? number? eq? not`.
`list` builds a proper list from its args.
`eq?` is true for equal numbers, equal symbols, equal booleans, or two `[]`s.
`print` (variadic): print each argument's printed representation, items separated
by single spaces, then a newline; `(print)` prints just a newline.

**Printed representation** (used by both paths, so make it deterministic):
- integer → decimal; `#t`/`#f`; `()` for the empty list;
- a proper list → `(e1 e2 ...)` space-separated; a dotted pair → `(a . b)`;
- a symbol → its name.

**`prim-eval`** is a special builtin used by self-host programs:
`(prim-eval name arglist)` applies the host primitive `name` (a symbol) to the
(already-evaluated) proper list `arglist` and returns its result. Direct programs
don't need it, but it must exist so that a meta-circular harness can delegate
primitive work (like `+`, `<`, `print`) back to your native implementation.

### Error handling (the malformed hidden case probes these)
- evaluating an unbound symbol in a context that requires a value** (e.g.
  arithmetic) → print `error: ...` to stderr and exit 1;
- division by zero → stderr line containing `division by zero`, exit 1;
- any syntax/parse failure → stderr + exit 1.
In all cases `print` a single `error:`-line and exit nonzero. Do not emit a
Python traceback; raise the recursion limit comfortably (e.g.
`sys.setrecursionlimit(1000000)`).

### Two levels of interpretation (the core requirement)

To make `self_host.txt`, the "**self-host harness**" `/app/samples/self.lsp` is a
Liz program that re-implements evaluation in Liz itself: it defines `ev`,
`apply2`, `lookup`, `primitives`, etc., and `(run-prog (quote (...)))` evaluates a
target program (as quoted data) through that meta-circular `ev`. Interpreting
`/app/samples/fib.lsp` directly and interpreting `self.lsp` (which runs the same
*fib* target via its own meta-circular evaluator — one extra nesting level) must
produce **byte-identical output**. Your `eval.py` must be faithful enough of the
Liz spec (real closures, `define` at top level threaded as a running env, correct
`if`/`quote`, and `prim-eval`) that this kind of harness—copy-of-the-own-loader
running another program—yields identical results for the visible and hidden
programs.

`/app/self_host.txt` must equal the output of
`python3 /app/eval.py /app/samples/self.lsp` (which the oracle verifier also
independently equals to `python3 /app/eval.py /app/samples/fib.lsp`).

The verifier re-runs `eval.py` on new hidden targets, each run **directly** and
through the same-style harness `hosted.lsp`, comparing all three (direct, hosted,
and the expected file):

- target `case_list` prints results built from `cons`/`car`/`cdr`/`quotient`;
- `case_fib` defines a recursive fib via en explicit fix-point pattern and prints
  (must handle closures and recursion through the meta-circular `ev`);
- `case_quote` exercises `quote`, `cons`+`quote` building a proper list printed as
  `(1 2)`, multiplication of negatives, `if`+`null?`, and an immediately-applied
  `lambda`;
- `case_div0` is a malformed program that must be rejected (`division by zero`).

If `eval.py` is correct, the hosted output always equals the direct output,
because the self-host harness is a faithful interpreter of the same language
you documented.

---

## Constraints recap
- Everything under `/app`. Never modify `/app/tools` or the `/app/samples`
  fixtures that ship in the image.
- The verifier **recompiles `/app/mips_interp.c` and re-runs it and
  `/app/classify.py` and `/app/eval.py`** on hidden inputs, so they must
  generalize — no hard coding to the visible sample values.
- Output files must match byte-for-byte; don't add banners.
- Make `/app/mips_interp.c` self-contained ANSI C (only `stdio/stdlib/string`
  and `stdint.h`); compile it with a plain `gcc -O2`.