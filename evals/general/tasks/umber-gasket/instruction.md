# umber-gasket — build four small, self-contained computation engines

You must produce four deliverable files under `/app`. Each is a hand-built mini
program/engine; there is no big framework to wire up. All four deliverables are
executed by the verifier against hidden inputs, so they must be complete,
correct, and general — never hard-code the answer to a specific input.

The four engines are independent. Work in `/app` and never read or modify
anything under `/tests`.

---

## 1. `/app/eval.py` — a Scheme-like evaluator with stdin pass-through and self-interpretation

### 1.1 What it is

A reader + interpreter for a small Lisp/Scheme-like language called **M**. An
`.m` file is a sequence of S-expressions. `eval.py` parses them, evaluates them
in order, and whatever the program prints with `(print ...)` goes to stdout.

### 1.2 Standard-input contract (required)

`eval.py` should expect stdin with two parts:

1. The **first line** is the path (absolute) of the M program file to run,
   e.g. `/app/foo.m`.
2. **Every remaining line** of stdin is *relayed* to that program: it becomes
   the interpreted program's input stream, consumed with `(read-int)` / `(read)`
   / `(eof?)`.

So if `eval.py` receives

```
/app/p.m
7
11
29
```

then program `/app/p.m` sees `7`, `11`, `29` on its input. If a program never
reads, the relayed lines are simply not consumed. Reading past the end yields
`#f`; once exhausted, `(eof?)` is `#t`.

The path comes from the **first stdin line** (not argv). Printing goes to
stdout only.

### 1.3 The M language

Tokens: parentheses, integer literals, double-quoted strings, and symbols.
`#t` / `#f` are the booleans. Lines that start with `;` are comments (skip
them).

Expression forms:

- integers, strings, booleans — self-evaluating;
- a symbol — its value in the environment;
- `(define name expr)` — bind `name` to the value of `expr`;
- `(define (name p1 p2 ...) body ...)` — bind a (possibly recursive) function;
- `(lambda (p ...) body ...)` — a closure;
- `(if c t f)` — value of `t` if `c` is not `#f`, else `f`;
- `(begin e ...)` — sequential, value of the last;
- `(quote x)` and its shorthand `'x` — the literal `x` as data, unevaluated;
- application `(f a1 a2 ...)` — apply `f` to the evaluated args.

Builtins:

- arithmetic `+ - * /` (variadic; `/` is integer division);
- comparison `= < > <= >=`; `eq?`; `not`;
- list ops `cons`, `car`, `cdr`, `null?`, `pair?`, `list?`, and `list`
  (build a list from its args);
- predicates `number?`, `string?`, `symbol?`;
- I/O `(read)`, `(read-string)`, `(read-int)`, `(eof?)`;
- output `(print x)` — printed representation of `x` + newline; `(display x)`
  — no newline;
- `(apply f lst)` — apply function `f` to the list `lst`.

Printed representations: integer → its decimal digits; boolean → `#t`/`#f`;
string → `"content"`; symbol → the symbol; list `(a b c)` → `(a b c)` with the
items space-separated and nested lists recursive.

### 1.4 Self-interpretation

Your evaluator must be able to run an **M program that is itself an interpreter
for a subset of M** — i.e. the evaluator's semantic kernel re-expressed in the
language itself (a *self-interpreter* / meta program). Such a program:

- defines helpers and recursive functions (with `define`/`lambda`),
- extracts list fields with `car`/`cdr` (and helpers `cadr`, `caddr`, ...),
- dispatches on symbols with `eq?`,
- walks nested subject data with `if`, function application and `begin`,
- prints one result at the end.

Given a meta program `P` that interprets a subject expression `S`, running
`eval.py` on `P` must produce exactly the same printed output as evaluating `S`
directly. This is the "one extra interpreter nesting level" (self-interpretation)
requirement: your evaluator must be a real, general evaluator, not a fixed
program runner.

### 1.5 What the verifier checks for eval.py

The verifier runs `eval.py` on hidden `.m` programs and compares every printed
line against an independent expectation:

- a **relay** program that reads integers from its relayed stdin until EOF and
  prints the sum (the verifier asserts the sum of the relayed lines);
- **meta** programs that re-implement the interpreter in M and interpret a
  hidden subject expression over the operators `+ - * sq cub twice` and `if`
  with `<` / `<=` / `>` / `>=` / `=` comparison; the expected line is that
  subject's value computed by the verifier's own reference. Different hidden
  subjects are used, so hard-coding a single answer cannot pass.

Your `eval.py` must parse and run arbitrary M, expose the relayed stdin to
`(read-*)`, and produce the exact required lines.

---

## 2. `/app/moves.fen.rules` — a pipelined-regex chess legal-move generator

### 2.1 Problem

A legal-move generator for a board that holds **exactly one white knight** on an
otherwise empty board (no other pieces). The legal "next positions" are all FEN
strings that equal the starter except that the knight moved to an on-board
square reachable in a knight move: from square `(r,c)` the destination is one of
`(r±2,c±1)` or `(r±1,c±2)`, with `0 ≤ r,c ≤ 7`. On an all-empty board every such
destination is empty, so all of them are legal.

### 2.2 Deliverable: an ordered list of regex-rewrite pairs

`/app/moves.fen.rules` is a **JSON array** of two-element arrays

```
[ "PATTERN", "REPLACEMENT" ]
```

an *ordered pipeline of regex substitutions*. There is no runtime move loop:
the moves come out of applying these `[pattern,replacement]` string rewrites.
Each generated output FEN names one legal next position.

Recommended authoring: make each rule p a *source* FEN (the knight on some
source square) and the replacement a *target* FEN (the same board with the
knight relocated to an on-board destination). Cover every legal destination for
every possible knight-bearing starting FEN of this shape, so that any hidden
starting FEN (any knight square) enumerates exactly its legal set. You may
write the rules by hand or generate the file with a throw-away script — the
deliverable is the finished `moves.fen.rules`.

### 2.3 Engine semantics (the verifier applies this - match it)

Given a starting FEN, the verifier treats each rule's `PATTERN` as a regex and
its `REPLACEMENT` as the emitted FEN text, in order:

1. For each `[pattern, replacement]` rule it tests
   `re.fullmatch(re.escape(pattern), startFEN)`.
2. Every rule that fires emits its replacement string as one candidate FEN.
3. The union of emitted candidates, minus any that equal the starter (a legal
   move is never the un-moved position), is the move list.
4. The move list is printed one FEN per line.

So each of your rules should match exactly the source FEN it describes (its
pattern is that source FEN) and emit the corresponding single target FEN as its
replacement. For any hidden starting FEN, the rules whose pattern matches fire
and yield exactly the legal-target set.

### 2.4 Verifier checks

Given each hidden starting FEN (corners, edges, centre, and one knight-less
board), the verifier computes the legal next-position set with an independent
geometric reference, runs `moves.fen.rules` through the §2.3 engine, and
asserts: (a) output-line count equals reference count; (b) the set of output
FENs equals the reference set; (c) no output line is the starter itself; (d) no
duplicate lines; (e) a knight-less FEN yields an **empty** output set; (f) every
output line is a valid single-knight FEN (one `N`, same suffix).

---

## 3. `/app/gate_net.txt` and `/app/simulate.py` — a combinational gate network

### 3.1 Semantics

`GateNet(n) = fib(floor(sqrt(n)))` for integer `n` in `[0,127]`.

```
fib(0)=1, fib(1)=1, fib(2)=2, fib(3)=3, fib(4)=5, fib(5)=8, fib(6)=13, fib(7)=21,
fib(8)=34, fib(9)=55, fib(10)=89, fib(11)=144, ...
floor(sqrt(n)) = the integer n-th square root
GateNet(n)     = fib( floor(sqrt(n)) )
```

Examples: `GateNet(16)=fib(4)=5`; `GateNet(100)=fib(10)=89`; `GateNet(1)=1`;
`GateNet(0)=1`.

### 3.2 `/app/gate_net.txt` — flat combinational net

Lines `NAME = EXPR` where EXPR is one of:

- `0` / `1`  (constant);
- a wire identity name;
- `& A B` (AND), `| A B` (OR), `^ A B` (XOR);
- `~ A` (NOT).

The file's first line is

```
INPUTS n0 n1 n2 n3 n4 n5 n6
```

(seven input bits, LSB first: `n = sum(n_i << i)`), and its second line

```
OUTPUTS f0 f1 f2 f3 f4 f5 f6 f7
```

(eight output bits, LSB first: `GateNet(n) = sum(f_i << i)`). Intermediate
wires may appear and must be defined before use. Your `gate_net.txt` must
implement `GateNet` exactly for all `n` in `[0,127]`.

### 3.3 `/app/simulate.py`

A tiny CLI:

```
python3 simulate.py <netfile> <n>
```

Reads `<netfile>` (3.2 format), evaluates the network on input `n` (0..127),
and prints the integer `GateNet(n)` on stdout. It must handle a large multi-
layer net without crashing.

### 3.4 Verifier

The verifier parses `/app/gate_net.txt` with its own reference simulator and
runs `/app/simulate.py` on a hidden batch of n (the square inputs 0,1,4,9,16,
25,36,49,64,81,100,121, their ±1/±2 neighbours, and edges 1,2,3,127). For each
n it asserts (a) its own simulation of your net equals `fib(floor(sqrt(n)))`,
and (b) `/app/simulate.py /app/gate_net.txt <n>` prints exactly that integer.

---

## General rules

- Only the four files above are checked; extra scratch scripts you leave in
  `/app` are allowed.
- `/app/eval.py` and `/app/simulate.py` must run with plain `python3`; no
  interactive session; print nothing extra on stdout.
- Exact formats matter: `eval.py` prints one line per `(print)`;
  `simulate.py` prints one integer; `moves.fen.rules` is strictly a JSON list
  of two-element arrays.
- Do not read `/tests`, and never hard-code any specific input's answer — every
  deliverable is re-run on hidden inputs.