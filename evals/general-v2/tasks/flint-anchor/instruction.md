# flint — toolchain & proofs microcosm (5 subsystems)

You are restoring the `flint` runtime toolchain after a botched merge. The
toolchain has five subsystems that have regressed or were never completed.
Your job is to **repair or finish** each one at its exact path and in some cases
to **build and run** artifacts from them, so that every deliverable below holds.

The project already ships a set of fixtures under `/app`:

```
/app/samples/traces.txt      stack-sample input for the profiler grouper
/app/vm/sweep.h              GC sweeping interface (do NOT edit)
/app/vm/sweep.c              GC sweeping implementation (has a bug)
/app/math/Sum.hpp            C++ header implementing a constexpr pack sum (broken)
/app/lib/core.c              shared library used by the default IR build
/app/ir/emit.s               emitted IR assembly for the default build
```

You must not modify anything in `/app` except the five deliverables listed
below. Work in the darwin home as needed but the verifier only checks the
five paths listed in **Deliverables**. You may create helper files, but note
the exact paths and file names required.

The system's `gcc`/`g++`/`binutils`/`make`/`python3` are already installed.

---

## Deliverables (verify every one)

1. `/app/callsites.py` — call-site profiler grouper (executable script).
2. `/app/vm/sweep.c` — corrected GC sweeping implementation.
3. `/app/math/Sum.hpp` — corrected C++11 `constexpr` pack-sum header.
4. `/app/mkbin.py` — executable (re)builder from emitted IR (executable script).
5. `/app/sections.py` — ELF section / symbol-string resolver (executable script).

Plus one **produced artifact**: build `/app/bin/flint_app`, a runnable
executable assembled from `/app/ir/emit.s` and linked against
`/app/bin/libcore.so` (built from `/app/lib/core.c`).

---

## Module A — call-site grouper (`/app/callsites.py`)

A call site for a profiler is identified by the **top three innermost frames**
of a stack sample. A trace with **fewer than three frames** still contributes
a site equal to its **whole frame list** (its available top frames).

Input: a text file with **one stack sample per line**; frames are separated by
`;`. Empty lines are ignored. Frames may have any characters except `;`.

Rule: the implied key of a sample is `";".join(top three innermost
frames)`. The innermost frame is the **first** token on the line.

Output: to stdout, exactly the **top-10** sites by **descending count**; ties
are broken by **ascending key** (lexicographic, bytewise). Each line is
`COUNT KEY` (a single space between them), one per site. Include at most ten
lines; include fewer if there are fewer distinct sites.

Edge cases to handle exactly:
- fewer than 3 frames -> the whole frame list is the key (e.g. a 2-frame
  sample `b;a` keys `b;a`).
- empty/blank lines are ignored and never counted.
- keys are case-sensitive and byte-exact.

Usage: `python3 /app/callsites.py <sample-file>` (also works if invoked with
no argument, defaulting to `/app/samples/traces.txt`).

The verifier runs it on a visible sample and on several hidden trace files.

## Module B — GC major-heap sweeping (`/app/vm/sweep.c`)

`/app/vm/sweep.c` implements the run-length-compressed (RLE) free-space sweep
of the major heap. A regression was introduced in it. Fix it.

Read `/app/vm/sweep.h` for the exact contract. In short, `sweep(live, size,
out, capacity)` receives a byte bitmap `live` (`live[i]==0` means heap word
`i` is dead/free), and must write to `out` one `run_t` for **every maximal run
of consecutive free words** as `{start, len}`, in increasing `start` order,
with these invariants always true:
- `len` is exact: the run covers exactly words `[start, start+len)`.
- `start+len <= size` (a run never extends past the heap).
- a run never covers a live word (`live[w]!=0`).
- contiguous free words are **coalesced into a single run** (the RLE
  property).
- covering words `[0,size)` with `live==0` are covered exactly once.

The line marked with a comment indicating the run length is where the bug
lives: it currently adds `+1` to the true run length. Correct it so the RLE is
exact. Return the number of runs written (never more than `capacity`).

The verifier compiles `sweep.c` together with an independent driver that
compares your `sweep()` against a brute-force reference on adversarial fixed
bitmaps and many seeded random heaps, and checks the RLE invariants directly.

## Module C — C++11 `constexpr` pack sum (`/app/math/Sum.hpp`)

`/app/math/Sum.hpp` provides a template `Sum<unsigned...>` whose contract is:

- `Sum<>::value == 0`.
- `Sum<A, B, ...>::value` is an **integer constant expression** equal to the
  arithmetic sum of the pack.

The header ships with a **post-C++11** implementation that will not compile
cleanly under strict C++11 and does not expose a usable constant-expression
`value`. Rewrite the template body so that the **public signature stays
`Sum<unsigned...>::value`**, the file compiles cleanly under
`g++ -std=c++11 -Wall -Wextra -pedantic-errors -Werror`, and `value` is usable
in `static_assert`, array sizes, and template arguments. Use only C++11-valid
`constexpr` constructs (recursive pack expansion is the intended approach —
no relaxed-constexpr bodies, no loops, no local mutation inside a `constexpr`
context). Do not rename `Sum` and do not change the member name `value`.

The verifier compiles a test translation unit that includes `/app/math/
Sum.hpp` and `static_assert`s the exact sums of many packs (including the
empty pack and single-element packs), and also uses `Sum<...>::value` as an
array size.

## Module D — (re)build a runnable executable from emitted IR (`/app/mkbin.py`)

`/app/mkbin.py` is a tool that assembles an emitted IR assembly file, links it
against a project shared library (which exports a C function the IR calls),
and produces a **runnable executable** at a requested path.

Interface:
```
python3 /app/mkbin.py <ir.s> <libcore.so> <output-executable-path>
```
It must produce an executable that:
- is assemble+linking via `gcc -no-pie` (`-no-pie` keeps the direct PLT calls
  simple);
- sets an rpath so the passed shared library is resolvable at run time from
  wherever the executable is placed (link the library by absolute path and
  add `-Wl,-rpath,<dir-of-library>`);
- runs and prints the result computed by calling the C function in the shared
  library (each IR file calls the library's function and `printf`s its decimal
  result on a single line, then exits 0).

The IR assembly is `x86-64 ELF` assembly (AT&T syntax). It declares `main`,
calls `printf@PLT` to print a `%d` of the value returned by the library
function `core_answer(int)` / `core_double(int)`, then exits 0.

Your deliverable does two things:
1. It must exist and work as the tool above, and
2. you must use it to build the **visible** default artifact:
   ```
   gcc -shared -fPIC -o /app/bin/libcore.so /app/lib/core.c
   mkdir -p /app/bin
   python3 /app/mkbin.py /app/ir/emit.s /app/bin/libcore.so /app/bin/flint_app
   ```
   so that `/app/bin/flint_app` is present and runnable, and running it prints
   a single decimal integer (the library's result for the IR's arguments).

The verifier re-runs `mkbin.py` on **hidden** IR + library pairs (3 cases) and
runs each produced executable, comparing its stdout to the expected value, and
also runs the visible `/app/bin/flint_app`.

## Module E — resolve sections & symbol-string tables (`/app/sections.py`)

`/app/sections.py` is an ELF analyzer using only `struct` (no external
libraries). For an ELF file path argument it prints, to stdout:

```
SECTIONS <n>
<idx> <name> <vaddr> <size>     # one line per section header, in offset order
SYMBOLS <m>
<value> <name>                  # one line per matching symbol, in symtab order
```

Where:
- `<n>` is the number of section headers (`e_shnum`).
- for each section `i`, `<idx>` is the index, `<name>` is its name resolved
  through the section-name string table (`e_shstrndx`) as a NUL-terminated
  string, `<vaddr>` is `sh_addr` (decimal) and `<size>` is `sh_size` (decimal).
- `<m>` is the number of symbols that match: from the table of type
  `SHT_SYMTAB` (if any), each symbol whose type (`st_info` low 4 bits) is
  `STT_FUNC`(2) or `STT_OBJECT`(1), single and whose name (resolved via the
  linked string table at `sh_link`) is non-empty. `<value>` is `st_value`
  (decimal), `<name>` the resolved NUL-terminated name. Symbols are emitted in
  natural symbol-table order.
- if there is no `SHT_SYMTAB` table, print `SYMBOLS 0`.

Your tool must produce this exact output including for binaries built/dealt
with by Module D (so it must cope with dynamic, non-PIE ELF executables and
their `.symtab`/`.strtab`).

Usage: `python3 /app/sections.py <elf-file>`.

The verifier runs it on the visible executable and on several hidden ELF files
(including ones produced by the hidden IR builds) and compares your output
line-for-line against an independent reference parser.

---

## Grading

The verifier runs each deliverable on the visible fixture(s) and on hidden
inputs, and awards a passing reward only when **all** five subsystems pass.
There must be exactly the formats described above — the comparisons are
byte/line-exact. Keep the deliverables at their exact paths, keep the produced
artifacts, and make sure `/app/bin/flint_app` really runs and prints the value.

Good luck.