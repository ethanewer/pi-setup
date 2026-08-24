# Synthesizing bit-level combinational circuits

You are working with *combinational netlists*: straight-line circuits made of single
word-at-a-time gates over fixed-width bit-vectors. You must synthesize (from scratch,
in C) two small netlists that evaluate two pure arithmetic functions, and emit them as
text files.

The whole task is offline and deterministic. Everything is below. Solve it by writing a
single C program, compiling it with `gcc`, and running it.

## Fixed width, word arithmetic

Every netlist operates on **unsigned bit-vectors of a fixed width `W`**. Every value is
an integer in `[0, 2^W)`. Add, subtract, multiply, shift, and bitwise operations are all
taken **modulo `2^W`** (i.e. they wrap). Comparisons return exactly `0` or `1`.

## Netlist file format

A netlist is a plain text file. Blank lines and lines starting with `#` are ignored.
The first meaningful line must be:

```
WIDTH <W>
```

followed by zero or more gate lines, and at the end one or more `OUT` lines. A gate line
has the form `<op> <id> <operands...>`, where `id` is the gate's unique non-negative
output id. **Ordering invariant:** every operand id on a line must be *strictly smaller*
than that line's `id` (this is what makes the circuit a topological DAG and lets it be
evaluated left-to-right). No two gates share an id, and ids need not be dense.

Recognized operations:

| Op    | Line                                      | Semantics (mod 2^W)             |
|-------|-------------------------------------------|---------------------------------|
| `IN`  | `IN <id> <k>`                             | input word number k (k>=0)      |
| `C`   | `C <id> <v>`                              | constant word v, **0 <= v < 2^W** |
| `ADD` | `ADD <id> <a> <b>`                        | `(a + b) mod 2^W`               |
| `SUB` | `SUB <id> <a> <b>`                        | `(a - b) mod 2^W`               |
| `MUL` | `MUL <id> <a> <b>`                        | `(a * b) mod 2^W`               |
| `AND` | `AND <id> <a> <b>`                        | bitwise a & b                   |
| `OR`  | `OR <id> <a> <b>`                         | bitwise a \| b                  |
| `XOR` | `XOR <id> <a> <b>`                        | bitwise a ^ b                   |
| `NOT` | `NOT <id> <a>`                            | bitwise ~a within W bits        |
| `SHL` | `SHL <id> <a> <k>`                        | `a << k` (k is a constant, 0<=k<W) |
| `SHR` | `SHR <id> <a> <k>`                        | `a >> k` (k constant, 0<=k<W)   |
| `LT`  | `LT <id> <a> <b>`                         | 1 if a < b (unsigned), else 0   |
| `EQ`  | `EQ <id> <a> <b>`                         | 1 if a == b, else 0             |
| `IF`  | `IF <id> <c> <a> <b>`                     | a if c != 0, else b             |
| `OUT` | `OUT <port> <id>`                        | declares output port; `id` must already exist |

Notes:

- Operative semantics: an execution reads input words by their index k (input 0
  is the first word) via `IN` gates and evaluates every gate once in increasing id order.
- You are allowed to reference a constant gate in many later gates (a DAG, not a tree).
- All arithmetic wraps modulo `2^W`. Watch out: intermediate products can wrap. For the
  square-root circuit, keep every squared value below `2^W` so nothing wraps (see below).

## 2. Two netlists you must produce

### File 1: `/app/sqrt_32.ng`
- `WIDTH 32`
- One input word, index 0: an unsigned integer `x` with `0 <= x < 2^32`.
- One output, port 0: **floor(sqrt(x))** (the largest integer `r` with `r*r <= x`).

Constraint you must respect so products never wrap: floor(sqrt(x)) is at most
`2^16 - 1 = 65535` when `x < 2^32`, and `65535*65535 < 2^32`. Do **not** form products of
candidates larger than `2^16` in a way that would wrap; i.e. search only the 16 low bit
positions (`2^15` down to `2^0`).

A natural construction is the classic **bit-by-bit square-root search** (sometimes called
the binary digit / non-restoring method): initialise a running root `q := 0`; for each
candidate bit `b` from `2^15` down to `2^0`, tentatively `t := q + b`; let `p := t*t`
(no wrap per the constraint); keep the bit iff `t*t <= x` (equivalently `p <= x`), i.e.
set `q := t` when `p <= x`, else leave `q` unchanged. That is exactly a sequence of
`ADD`, `MUL`, `LT`, `EQ`, and `IF` gates, topologically ordered.

### File 2: `/app/fib_64.ng`
- `WIDTH 64`
- One input word, port 0: an index `k` with `0 <= k <= 64`.
- One output port 0: the Fibonacci number `F(k)` where `F(0)=0`, `F(1)=1`, `F(n)=F(n-1)+F(n-2)`.

Constraint: `F(64) = 10610209857723 < 2^63`, so all intermediate `ADD`s fit without wrapping.
The circuit is combinational; `k` is not known at build time, so build it by **unrolling**
the recurrence for all indices `0..64` (using `ADD` gates only: `f2=f1+f0`, `f3=f2+f1`, ...)
and then **select** the demanded one with a compare-and-select chain: start the result at
`F(64)`; for `i = 63 .. 0`, replace `result` with `F(i)` exactly when `k == i`. "When `k == i` a constant `i` can be brought in with `C` gates, and the replacement is `IF(EQ(k,i), F(i), result)`.
- Do not use a loop that depends on a runtime value; everything must be straight-line
  (fixed number of gates regardless of k).

## 3. Deliverable

Write a single self-contained C program `/app/build.c`. Compile and run it:

```
gcc -O2 -o /app/build /app/build.c
/app/build
```

It must write exactly the two files `/app/sqrt_32.ng` and `/app/fib_64.ng` described
above. A hidden harness (not shown to you) will load each file, check it is a valid
topologically-ordered netlist (every operand id strictly less than its gate id, every
constant `< 2^W`), then evaluate it on many inputs and compare `floor(sqrt(x))` and
`F(k)` against ground truth. Both netlists must be correct to score full reward; partial
credit is awarded if exactly one of the two is fully correct.

Build the circuit generators with small helper functions that allocate new ids so that
ordering stays trivial and you never reuse an id. Before scaling to the full width, test
your emit/format on a tiny width (e.g. `WIDTH 4`, `IN`, `C`, `ADD`, `OUT`) and confirm the
file parses and evaluates. Then roll out the full construction.