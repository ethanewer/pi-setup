# Zephyr Summit toolchain build-out

You are standing up a complete developer toolchain from scratch inside this Ubuntu-24.04
container, then using it to produce a coherent set of artifacts. Work only in `/app`,
`/app/proofs`, and any scratch directories you create. The grader checks every deliverable,
and it also re-runs several of your tools on new, hidden inputs, so build things that
generalize — do not special-case the exact fixtures shown here.

The five deliverables (all must exist and pass):

1. `/app/vendor/bin/cc`         — a working C compiler driver built from the provided clean-room source
2. `/app/sections.txt`          — ELF section + symbol dump of a binary you compiled
3. `/app/proofs/thm` (plus `/app/proofs/thm.v`, `/app/proofs/thm.vo`) — a compiled Coq proof object
4. `/app/artifact/runner.jar`   — a runnable assembly JAR built from a Scala project
5. `/app/bin/symexec`           — an on-PATH symbolic execution engine (executable)

The rest of this document is the exact contract for each one; follow it precisely.

---

## 1. Compiler from source — `/app/vendor/bin/cc`

A small, self-contained C compiler ("zcc", ~800 lines) is provided in source form at
`/app/cc-src/cc.py`. It is an original clean-room implementation of a practical C subset
(`int` scalars and arrays, arithmetic and comparisons, `if`/`while`/`for`, functions,
global variables, and `printf`-style calls) that lowers each function to x86-64 assembly
and then assembles/links the result with the system `gcc`/binutils. It is deliberately
general: anything expressible in the subset compiles — do not hard-code the fixtures.

Install it as the required deliverable (the installed file must be executable and
accept the interface `cc -o <out> <in.c>`):

```
mkdir -p /app/vendor/bin
install -m 755 /app/cc-src/cc.py /app/vendor/bin/cc
```

You may add a short smoke test before moving on, e.g.
`/app/vendor/bin/cc -o /tmp/smoke /tmp/smoke.c && /tmp/smoke`.

The grader will compile **hidden C programs** with `/app/vendor/bin/cc -o <bin> <src.c>`,
run `<bin>`, and compare its stdout to the expected output. Your compiler must therefore
handle plain `stdio.h`-based programs written within the supported subset: multiple
declarations in one `int ...;` statement (with or without initializers), `for` loops
(including `i++`/`i = i + 1` steps), `+=`/`-=` compound assignment, blocks `{ ... }`,
read/write of global and local integer arrays (`data[i] = f(i);`), user functions with
`int` parameters and `return`, and `printf("%d\n", ...)` calls.

### Deliverable 2 — `/app/sections.txt` (built on top of deliverable 1)

Compile the provided C program with your own compiler, then dump its ELF structure with
`readelf`:

```
/app/vendor/bin/cc -o /app/bin/probe /app/fixtures/probe.c
readelf --wide --sections /app/bin/probe > /app/sections.txt
printf '\n== SYMBOLS ==\n' >> /app/sections.txt
readelf --wide --syms /app/bin/probe >> /app/sections.txt
```

`/app/sections.txt` is therefore the **exact** output of those two `readelf` commands, in
that order (sections headers, then the symbol table), against a binary produced by a
fresh run of your `/app/vendor/bin/cc`. The grader will re-run those same commands
against its own re-built `/app/bin/probe` and byte-compare the result, so recreate the
file with the exact commands above rather than hand-editing it, and do not modify
`/app/fixtures/probe.c`.

Note: the compiler emits its assembly to a fixed temporary path and links a fixed-name
object file, so rebuilding the same source yields a byte-identical ELF (and therefore an
identical `readelf` dump). Keep that property — do not introduce anything time- or
path-dependent into the pipeline.

---

## 2. Scala assembly JAR — `/app/artifact/runner.jar`

A small Scala 2.11 project is provided under `/app/fixtures/scalademo/` (two source files:
`Adder.scala` and `Runner.scala` in package `summit`). Build it into a **standalone
assembly JAR** at the exact path `/app/artifact/runner.jar` whose manifest declares
`Main-Class: summit.Runner`.

Because Scala requires its runtime library at run time, a plain `scalac` + `jar` will not
run under `java -jar`. You must bundle the Scala runtime classes into the JAR so it is a
true assembly/uber JAR. A reliable recipe against the Scala 2.11 distribution installed as
`/usr/share/java/scala-library.jar`:

```
mkdir -p /tmp/scbuild && cd /tmp/scbuild
cp /app/fixtures/scalademo/*.scala .
scalac -d classes Adder.scala Runner.scala
printf 'Main-Class: summit.Runner\n' > manifest.txt
jar cfm /app/artifact/runner.jar manifest.txt -C classes .
mkdir -p rt && cd rt && jar xf /usr/share/java/scala-library.jar   # extract runtime
rm -rf META-INF
cd /tmp/scbuild && jar uf /app/artifact/runner.jar -C rt scala
```

The grader will run `java -jar /app/artifact/runner.jar <a> <b> ...` with hidden integer
arguments and byte-compare stdout against the expected `RESULT <r>` line, where
`<r> = A.weigh(s)` with `s = a + b + ...` and `weigh(n) = n*n + 3*n + 7` (see the sources).
It must therefore work standalone with no `-cp` flags.

---

## 3. Coq proof object — `/app/proofs/thm` and `/app/proofs/thm.v`

A Coq 8.18 starter module is provided at `/app/fixtures/coq/thm.starter.v`. Copy it to
`/app/proofs/thm.v`, **complete every placeholder** (every `Admitted` / `(* TODO *)`) with a
real closing tactic script, then compile it:

```
mkdir -p /app/proofs
cp /app/fixtures/coq/thm.starter.v /app/proofs/thm.v
cd /app/proofs && coqc thm.v
cp thm.vo thm        # the deliverable is the compiled proof object
```

Rules the grader enforces:

- `/app/proofs/thm.v` must compile cleanly with `coqc` (exit 0) from a fresh copy in a scratch
  directory (i.e., no reliance on pre-existing `.vo` files).
- `/app/proofs/thm.v` must contain **no** `Admitted`, `admit`, `Axiom`, or `TODO` tokens
  (including in comments).
- `/app/proofs/thm.vo` and `/app/proofs/thm` must exist, and `/app/proofs/thm` must be byte-identical
  to what a fresh `coqc /app/proofs/thm.v` produces (the grader recompiles and compares).
- Do **not** change any lemma/theorem statement, type signature, or the two reference
  proofs already filled in.

The statements you must prove (all in the starter) are: `lsum_rep`, `revA_app`,
`revA_length`, and the hardest one `gauss` (which needs induction plus polynomial
arithmetic — `lia` alone will not close the induction step once products of `n` appear;
you will want `nia` or `ring_simplify` + `ring`/`nia` style reasoning).

---

## 4. Symbolic execution engine — `/app/bin/symexec`

Implement a small **symbolic execution engine** in Python and install it as the executable
`/app/bin/symexec`. Because `/app/bin` is already on `PATH`, it is then **globally
invocable** as `symexec <ir.json>` from anywhere.

The environment provides a Python 3 venv at `/opt/z3venv` with the `z3-solver` bindings
installed; use `/opt/z3venv/bin/python` as the interpreter (either as the shebang or to
create the executable). The `z3` command-line solver and the LLVM-16 toolchain
(`clang-16`, `llvm-config-16`) are also installed; your engine must confirm they are
present as part of a `--selftest` mode (see below).

### Input IR format (a JSON file, one per program)

```json
{
  "vars":  {"x":[-3,3], "y":[-3,3]},
  "ops":   [ ...instruction list... ],
  "goal":  {"var":"out", "eq":6}
}
```

- `vars` maps each integer input variable to its closed `[lo, hi]` domain. Variable names
  are unique strings; domain-var order in the output follows the order the keys appear in
  `vars`.
- `ops` is a straight-line list of symbolic instructions. Each produces a bounded
  variable (`dst`) from operands that are either an integer literal or the name of an
  earlier `dst` or an input variable. Supported ops:
  - `{"op":"set","dst":D,"val":<int>}` — bind `D` to the literal.
  - `{"op":"add"|"sub"|"mul","dst":D,"a":A,"b":B}` — arithmetic on integer expressions.
  - `{"op":"neg","dst":D,"a":A}` — negation.
  - `{"op":"ite","dst":D,"cond":[L,CMP,R],"a":A,"b":B}` — conditional value: evaluate the
    comparison `L CMP R` (over integer expressions) and bind `D` to `A` if true else `B`.
    `CMP` is one of `LT`, `LE`, `GT`, `GE`, `EQ`, `NE`.
- `goal` asks for values of the input variables (within their domains) such that the final
  expression bound to `goal.var` is numerically **equal** to `goal.eq`.

### Behaviour / output contract

`symexec <ir.json>` symbolically evaluates the program (building symbolic expressions over
the input variables), uses the z3 constraint solver to find **every** assignment of input
variables (within their domains) that makes `goal.var == goal.eq`, and prints them:

- one assignment per line, as `x=3,y=-1` — fields joined by `,`, each field `name=value`,
  in the exact order the variable names appear in the `vars` object;
- lines sorted lexicographically by the resulting tuples;
- if no assignment satisfies the goal, print exactly `NO_SOLUTION`.

`--selftest` mode must verify the toolchain is present and usable. It should exit 0 and
print one line starting with `SELFTEST_OK` that also reports the z3 version and the
LLVM-16 presence, e.g.:
`SELFTEST_OK z3=<major>.<minor>.<build> llvm16=<yes|no>` (the `llvm16=yes` part is
required).

A sample IR is at `/app/fixtures/sym/sample1.json` and its expected output at
`/app/fixtures/sym/sample1.out` — run `symexec /app/fixtures/sym/sample1.json` and diff
against the `.out` file to confirm your engine before finishing (`diff
<(symexec /app/fixtures/sym/sample1.json) /app/fixtures/sym/sample1.out`).

The grader will run your `symexec` on hidden IR files (different variable domains, ops and
goals, including a `NO_SOLUTION` case) and compare stdout byte-for-byte.

---

## General rules

- Do not modify anything under `/app/cc-src` (the vendored clean-room compiler source),
  `/app/fixtures`, or the installed system toolchains. You build from them.
- All five deliverables must be present and pass when the grader runs. Prefer clean,
  general generalizable implementations over fast special cases.
- `/app/sections.txt` must be produced by the exact `readelf` commands listed, against a
  binary built by your own `/app/vendor/bin/cc`.