# zephyr-forge — the ForgeWorks analysis shop

You are building a suite of **six numerical-optimization / solver CLIs** for a
metalworks ("ForgeWorks") engineering office. Each CLI solves one well-defined
sub-problem, is a standalone `python3`-runnable script under `/app`, and must
generalise to **any** input that follows the documented format — the automated
verifier runs your CLIs on fresh hidden inputs.

The fixed **visible case** is at `/app/case/` (read it; never modify it). To
produce the deliverable result files you run each CLI on the visible case. The
inputs of the hidden cases use exactly the same file layout but different data,
including edge / malformed variants described below.

---

## Deliverables (all must exist under `/app` at the end)

| path | kind |
|---|---|
| `/app/opt.py`            | CLI — mixed-integer `.mps` solver      |
| `/app/maxsat.py`         | CLI — weighted MAX-SAT exact solver   |
| `/app/quartic.py`        | CLI — quartic+quadratic optimizer     |
| `/app/corners.py`        | CLI — basic-feasible (corner) enumerator|
| `/app/verdicts.py`       | CLI — bit-vector verdict classifier   |
| `/app/compress.py`       | CLI — literal/back-ref packer (fixed format) |
| `/app/model.mps.optimized.txt` | result flag A |
| `/app/maxsat_solution.json`   | result, subproblem B |
| `/app/quartic_solution.json`  | result, subproblem C |
| `/app/corners.txt`            | result, subproblem D |
| `/app/sat_verdicts.txt`       | result, subproblem E |
| `/app/encode.bin`             | result, subproblem F |

Each CLI is executed by the verifier on the visible **and** hidden inputs, so
make them robust, exact, and deterministic. Never read `/tests` or anything
outside the paths you are given.

---

## A — `/app/opt.py`  (mixed-integer MPS solver)

Usage:

```
python3 /app/opt.py <model.mps> <out.txt>
```

Reads a **standard MPS** file describing a mixed-integer program (binary and
general-integer variables), solves it to the global optimum, and writes `out.txt`
as exactly one line:

```
OBJECTIVE <value>
```

where `<value>` is the optimal objective value of the model (a real number). The
`.mps` parser and numeric solver must be present and correct (any sound MIP
solver is fine — e.g. HiGHS, CBC/PuLP, OR-tools). The hidden `.mps` models are
small MIPs with a non-trivial integrality gap, so a solver that solves only the
LP relaxation or mis-handles integer variables will report the wrong value.

Visible result: run

```
python3 /app/opt.py /app/case/model.mps /app/model.mps.optimized.txt
```

---

## B — Weighted MAX-SAT  (`maxsat.py`)

Usage:

```
python3 /app/maxsat.py <instance.txt> <out.json>
```

`instance.txt` format:

```
VAR <n>                     # boolean variables are numbered 1..n, one line
HARD                        # followed by zero or more hard-clause lines
<lit> <lit> ...            # a clause: space-separated non-zero ints
SOFT                      # followed by zero or more soft-clause lines
<weight> <lit> <lit> ...   # weight then a clause
```

A **literal** is a non-zero integer: positive `k` means variable `k` is true in
the clause, negative `-k` means variable `k` is false. A **clause is satisfied**
when **at least one** of its literals takes its sign-matched truth value. Hard
clauses are mandatory; soft clauses earn their non-negative integer **weight**
when satisfied.

Semantics: among all boolean assignments to variables `1..n` that satisfy
**every** hard clause, pick the assignment that maximises the **sum of weights of
satisfied soft clauses**. 

* If the hard clauses are jointly **unsatisfiable** (no assignment satisfies all
  of them), write
  ```
  {"status": "HARD_UNSAT"}
  ```
* Otherwise write
  ```
  {"status": "OPTIMAL", "objective": <integer max weight>}
  ```

This must be the **exact** global optimum. A heuristic/greedy value is a wrong
answer. Hidden instances include a satisfiable MAX-SAT with many variables and an
instance whose hard clauses are mutually contradictory.

Visible produced:

```
python3 /app/maxsat.py /app/case/maxsat.txt /app/maxsat_solution.json
```

---

## C — Quartic-plus-quadratic objective  (`quartic.py`)

Usage:

```
python3 /app/quartic.py <problem.txt> <out.json>
```

`problem.txt` defines a smooth convex objective over `n` real variables:

```
n <n>
a <a_0 ... a_{n-1}>                 # per-variable quartic coefficients (positive)
t <t_0 ... t_{n-1}>                 # per-variable quartic centres
c <c_0 ... c_{n-1}>                 # per-vector quadratic-penalty centre
penalty <p>                         # quadratic penalty coefficient (>=0)
coupling <k>                        # global quadratic-coupling scale (>=0)
start <s_0 ... s_{n-1}>             # suggested initial iterate
A <a plus n rows, one per row>  # n x n coupling matrix (symmetric, positive definite)
```

The objective is

```
f(x) = Σ_i a_i*(x_i − t_i)^4  +  p*||x − c||²  +  k * ½ * xᵀ A x
```

Note that `A` may be given either with the keyword `A` on its own line followed by
`n` rows of `n` numbers, or the keyword `A` followed immediately by the first row
(all rows after `A` are matrix rows). `#` begins a comment to end of line, ignored
everywhere. Missing values default to 0 or as shown.

Minimize `f` numerically (it is strictly convex with a unique global minimum).
Write `out.json`:

```
{"objective": <f(x*)>, "gradient_norm": <||∇f(x*)||>, "x": [x_0, ...], "success": true}
```

The verifier re-minimizes the same problem from a fixed start point and checks
that your `objective` matches its reference optimum and that `gradient_norm` is
small (near-stationary), so your answer must come from a real
optimizer (e.g. `scipy.optimize.minimize` with gradient `∇f`), not from a guess.

Visible produced:

```
python3 /app/quartic.py /app/case/quartic.txt /app/quartic_solution.json
```

---

## D — Basic-feasible (corner) enumeration  (`corners.py`)

Usage:

```
python3 /app/corners.py <instances.txt> <out.txt>
```

`instances.txt` is a whitespace token stream holding **one or more** LP
instances. Each instance is:

```
m n
<one row of A, n ints>   (following m rows in total)
<b_0 ... b_{m-1}>        (m ints)
```

Instances are concatenated back-to-back with no interleaving; blank lines and `#`
comments are ignored. You can read the whole file as a flat integer token list and
consume them as `m, n` then `m*n` (the `m` x `n` matrix `A`, row-major) then `m`
(the right-hand side vector `b`), and repeat. Repeat until tokens run out.

For each instance, an **basic feasible solution** (corner) of the nonnegative
linear program `{x in R^n : A x = b, x ≥ 0}` is produced by choosing a subset
`T` of **exactly `m`** columns of `A` that is invertible, solving `A_T x_T = b`,
and keeping that candidate only when every `x_T` entry is **≥ 0** and all
non-selected variables are `0`. Equivalent corners (same full vector reached
twice) are counted once; singular subsets are skipped.

Write, one integer per line, the **total number of distinct feasible corners**
for each instance, in the same order:

```
<count instance0>
<count instance1>
...
```

Use exact rational arithmetic to decide `≥ 0` and to deduplicate identical
vertices. Hidden instances include duplicate columns producing repeated corners,
square nonsingular systems, `m > n` (no basic feasible corner → 0), and
right-hand sides whose square solutions contain negative entries (also excluded).

Visible produced:

```
python3 /app/corners.py /app/case/corners.txt /app/corners.txt
```

---

## E — Bit-vector verdict classifier  (`verdicts.py`)

Usage:

```
python3 /app/verdicts.py <verdict_dir> <out.txt>
```

`verdict_dir` contains zero or more `*.txt` files (each the printed output of an
SMT/“bit-vector-constraint” solver for one query). For each `*.txt` file, in
lexicographic (sorted) filename order, you must decide whether the underlying
constraint set is **satisfiable (SAT)** or **unsatisfiable (UNSAT)**.

Classification rule (case-insensitive, applied to the file's full text):

* It is **UNSAT** if the text (lowercased) contains any of the substrings
  `unsat`, `no solution`, or `could not be solved`.
* Otherwise it is **SAT**.
* An **empty file** counts as **SAT**.

Exactly one `SAT` or `UNSAT` (that exact token, uppercased) per input file, one
per line, in sorted-filename order, written to `out.txt`. Hidden inputs include
assertion styles (e.g. `unSATISFIABLE`, `unsat core`, `no solution found`,
uppercase/lowercase and a file containing the bare token `sat` and a bearer empty
file).

Visible produced:

```
python3 /app/verdicts.py /app/case/verdicts /app/sat_verdicts.txt
```

---

## F — Literal/back-reference compression  (`compress.py`)

Usage:

```
python3 /app/compress.py <source.txt> <ceiling.txt> <out.bin>
```

`source.txt` is some text (bytes); `ceiling.txt` holds a single integer **byte
ceiling**. You must encode the text into `out.bin` with the **fixed** self-
delimiting format below, such that (1) decoding `out.bin` reproduces `source.txt`
byte-for-byte, and (2) `len(out.bin) < ceiling`.

**Fixed encoding format** — a sequence of instructions; each instruction is:

* `L` literal: tag byte `0x4C`, next **2 bytes little-endian** length `L`
  (1..65535), then `L` raw source bytes appended verbatim.
* `B` back-reference: tag byte `0x42`, next 1 byte **distance** `d` (1..255),
  then 1 byte **length** `L` (1..255). It copies `L` bytes starting
  `d` positions earlier in the output stream, allowing **overlap** (byte `k` of
  the copied run equals byte `(current_output_length − d + k)`, reading the output
  just as it has been built so far).

Decode must terminate exactly at the end of `out.bin`. Your job is to pick the
**literal-vs-back-reference segmentation** (e.g. with an optimal dynamic
programming over instruction costs) so that the encoded size lands strictly under
the ceiling. A naive “emit everything as literals” always produces
`3 + len(source)` bytes, which **exceeds** the ceiling for every case, so real
back-references are mandatory.

Visible produced:

```
python3 /app/compress.py /app/case/text.txt /app/case/ceiling.txt /app/encode.bin
```

---

## What must exist when you are done

* the six CLIs above (each `python3`-runnable, working on any input);
* the six result files produced by running them on `/app/case/`.

The verifier recomputes the expected results (for the visible case and for every
hidden case) and checks them against both your CLIs’ outputs on the hidden inputs
and the `/app` result files. Be exact — objective values, corner counts,
verdicts and compressed sizes all matter exactly as specified.