# Dune-Mantle — the Formal-verification Dossier

You are assembling a small formal-methods dossier. The box runs Ubuntu 24.04 with
`clang`/`opt`, the `z3` SMT solver (with `python3-z3` bindings), and `coqc` already
installed; LLVM tools are available under bare names (`clang`, `llvm-dis`, `llvm-as`,
`opt`, `llvm-link`, `lli`).

Your finished products must be exactly these two `/app` deliverables:

1. `/app/solve.py` — a terminal CLI solver.
2. `/app/answer.json` — a JSON dossier that records running deliverable 1 and one
   more artifact described below.

You additionally install ONE globally-invocable executable named `symxe` on `PATH`
(a symbolic-execution engine), and produce a Coq proof object. Everything below uses
only integer arithmetic and already-installed tools. All analysis is CPU-only.

## Deliverable 1 — `/app/solve.py`

A single Python 3 program with three independent subcommands. It may use the installed
`z3` module. Printed output is exact (see formats). `chmod +x /app/solve.py`.

### 1a. `python3 /app/solve.py wcnf <file>`

Read a Weighted Partial Max-SAT instance in **WCNF** format and print the optimum:

```
OPT <objective>
```

or `OPT UNSAT` if the hard clauses are unsatisfiable.

WCNF structure you MUST tolerate (these exact variations are tested):
- Lines starting with `c ` are comments (ignore).
- Blank lines are ignored.
- A `p wcnf <nvars> <nclauses>` header line (ignore it).
- A trailing lone `%` terminator is ignored.
- **Hard clauses** may be prefixed with the weight token `top`. Any hard clause —
  whether literally written `top` or as a number — must be enforced (the input uses
  the literal token `top` for hards).
- **Soft clauses** carry a positive integer weight (the first token).
- A clause is a list of non-zero signed literals terminated by `0`; a positive `n`
  means variable n true, `-n` means variable n false.

The **objective** is the sum of the weights of the satisfied SOFT clauses, subject to
all HARD clauses being satisfied. You must return the maximum achievable objective
(the optimum), not simply a feasible assignment's value.

### 1b. `python3 /app/solve.py qfbv`

Read an SMT-LIB script from **stdin** and print exactly one verdict line:

```
sat
```

or `unsat`, or `unknown` if the solver cannot decide or the input is malformed.

The scripts use logic `QF_BV` (quantifier-free fixed-width bit-vectors), declaring
bit-vector constants and asserting bit-vector constraints. Your program must accept
the input purely on stdin (do not require a filename), must not hang, and must exit
zero. You may strip `(set-logic ...)`, `(set-option ...)`, `(check-sat)`,
`(get-model)`, and `(exit)` before feeding the asserts to the solver; the verdict is
what matters.

### 1c. `python3 /app/solve.py seats <file>`

A discrete constraint-satisfaction "seating arrangement" problem. The file is a
text file with exactly these lines (order fixed):

```
people:A,B,C,...
focus:F
allies:P1-P2,P3-P4,...
enemies:P1-P2,P3-P4,...
```

Parse words `language: value` (ignore `#` comments). People is a comma list of
single capital letters (all distinct). `focus` is one of those letters. `allies`
and `enemies` are comma-separated unordered pairs written `A-B`.

A **board** is a circular seating arrangement, i.e. a permutation of all people
(case-sensitive letters only). A board is **legal** when ALL of the following hold:

- No two enemies sit adjacent (in the circular ring).
- Every person sits adjacent (in the ring) to **at least one** ally.
- The focus person sits adjacent to **two** people, **both** of whom are allies.

Output, one item per line, in this exact order:

```
FOCUS <letter>
PAIRS <letter>,<letter>
NBOARDS <n>
<board1>
<board2>
...
FIXPOINT <fixed_value>
PHRASE <phrase>
STEPS <m>
```

- `PAIRS` — sorted list of the letters that are adjacent to the focus in at least
  one legal board (outbound, so at most two, sorted by their ASCII).
- `NBOARDS` — the total number of distinct legal boards.
- Every legal board string, one per line, sorted. The focus letter is always the
  FIRST character of each board string (the ring is rotated so it is).
- `FIXPOINT` and `PHRASE` and `STEPS` — see the fixed-point rule below.
- Rotations/reversals that yield the same people in the same circular order are
  distinct if the strings differ; enumerate every distinct string.

**Spelled fixed-point rule.** Let `K = NBOARDS`. Spell `K` as a lowercase English
word, counting only the letters `a`–`z` (ignore hyphens `-`, spaces, separators).
Examples: `6` → `six` → 3 letters; `32` → `thirty-two` → 9 letters (the hyphen is not
counted); `1` → `one` → 3. Repeat: while the letter-count differs from the current
value, replace the current value by its letter-count. The value that stops changing
(where `letters(n) == n`) is the **fixed point**; `STEPS` is the number of
replacement steps taken, counting each transition (including the final step where
`letters(n) == n`). `FIXPOINT` is that fixed point value; `PHRASE` is its fully
spelled word with hyphens/separators removed (so `four` for 4). For tiny boards
this is often `4`/`four`, but compute it, do not assume.

## Deliverable 2 — the `symxe` engine (global `PATH`)

Install one executable named `symxe` on `PATH`. It is a symbolic execution engine
over LLVM bitcode for the integer subset emitted by `clang -O0`. Its behavior:

- `symxe --version` prints `symxe <version>` and exits 0.
- `symxe run <module.bc|module.ll>` symbolically executes the function literally
  named `target` (and only that), explores every reachable control-flow path, and
  prints, for each distinct terminal path, a concrete witness test input:

```
PATHS <n>
TEST <v0> <v1> ...
```

One `TEST` line per reachable terminal path, function parameters in declaration
order, as signed little-endian i32 values. It must cover BOTH/all branches (see
hidden cases). On any error — unreadable file, non-bitcode file, missing `target`
function, unknown instruction — it must print an error to stderr and exit NON-ZERO.

Run `symxe run` against the shipped fixture **`/app/seed/classify.c`** (a branching
`target` function). First compile it yourself:

```
clang -emit-llvm -c /app/seed/classify.c -o /app/work/classify.bc
symxe run /app/work/classify.bc > /app/work/classify.symx
```

`/app/work/` is created by you.

## Deliverable 3 — the Coq proof object

Write, by hand, a small Coq file `/app/cert/astral.v` that proves:
`commutativity of addition on naturals` (`forall n m, n + m = m + n`). Then compile it:
```
cd /app/cert && coqc astral.v
```
This produces the compiled proof object `/app/cert/astral.vo` from a clean compile.

**Restriction:** your `astral.v` may NOT contain, in any of its text (proofs,
comments, anywhere), any *automatic-search* tactic token — specifically none of:
`auto`, `eauto`, `tauto`, `intuition`, `firstorder`, `trivial`, `easy`, `now`,
`omega`, `lia`, `nia`, `psatz`, `ring`, `field`, `congruence` (and no
`crush`). Use explicitly-tactic proofs only (`induction`, `intros`, `simpl`,
`rewrite`, `reflexivity`, ...). Every helper-search token must be resolved into
concrete tactic statements so none is left behind.

## Deliverable 4 — `/app/answer.json`

After everything above is in place, produce `/app/answer.json` (JSON) whose `keys`
are exactly:

- `"wcnf_opt"` — integer: the OPTIMAL objective from **1a** on `/app/instance.wcnf`.
- `"qfbv"` — the verdict string from **1b** on stdin from `/app/qfbv_query.smt2`.
- `"seats"` — object: `{"focus": "<letter>", "pairs": [..], "nboards": <int>,
  "boards": [..], "fix": <int>, "phrase": "<str>", "steps": <int>}` from **1c**
  on `/app/seats.txt`.
- `"symxe"` — object: `{"engine": "symxe", "version": "<ver>", "paths": <int>}`
  where `paths` is the `PATHS` count in `/app/work/classify.symx`.
- `"cert"` — the string `"ok"`.

`/app/answer.json` must be a REAL artifact produced by RUNNING your tools (not a
hand-typed constant).

## Inputs already present (do not modify)

Interesting files already shipped in `/app`, and already laid out:

- `/app/seed/classify.c`
- `/app/seats.txt`
- `/app/instance.wcnf`
- `/app/qfbv_query.smt2`.

Do NOT modify these files. Do not delete `/app` except through your own work
under `/app/work` and `/app/cert`.

## Evaluation

Your submission is graded by re-running `/app/solve.py` and `symxe` on unseen
instances (weighted WCNF, QF-BV scripts, seatings, further bitcode modules,
plus malformed inputs) and by checking `/app/cert/astral.vo` and the absence of the
forbidden tactic tokens in `/app/cert/astral.v`. Your program must therefore
generalize — no hard-coded answers to the visible inputs; behave like a real harness
toolkit.

The only files you may write in `/app` are: `solve.py`, `work/*`, `cert/*`,
`answer.json`. Do not touch anything else.