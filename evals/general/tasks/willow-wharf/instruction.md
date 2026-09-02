# Willow Wharf — machine-checked reproducibility pack

`Willow Wharf` is the quantitative-research consultancy arm drafting a
reproducibility pack for its client **Braken Tide Consulting**. Four
toolchains each ship one auditable artefact. Every artefact lands in **`/app`**
and is re-verified from scratch by an independent grader, so your outputs must
reproduce on a fresh run, not just once.

You will author or finish **nine deliverables**:

| path             | what it is                                                        |
|------------------|-------------------------------------------------------------------|
| `/app/proof.v`   | completed Coq proof (finish the on-image file)                    |
| `/app/proof-check.log` | text record of running `coqc /app/proof.v`                  |
| `/app/integral.py` | sympy symbolic well-integrator over the unit interval          |
| `/app/integral.txt` | exact closed form of the fixed client integral                |
| `/app/sampler.R` | R script with the two required entry points                       |
| `/app/selftest.log` | output of that script's self-test routine                     |
| `/app/report.tex` | LaTeX memo, synonym-subbed free of over-full boxes               |
| `/app/report.pdf`  | the compiled memo                                              |
| `/app/pdflatex.log`| `pdflatex` log from a clean build of the memo                 |

Work only inside `/app`.

---

## 1. Coq proof — `/app/proof.v` (incomplete file already on the image)

`/app/proof.v` is placed on the image with a prototype induction that **is not
finished**: its two case steps still say `admit`. Complete it.

The module defines two recursive sums of the first `n` non-negative naturals,
accumulated in opposite directions:

```coq
Fixpoint sumup (n : nat) : nat :=
  match n with O => O | S k => sumup k + S k end.

Fixpoint sumdown (n : nat) : nat :=
  match n with O => O | S k => S k + sumdown k end.
```

Finish

```coq
Theorem sumup_eq_sumdown : forall n : nat, sumup n = sumdown n.  (* prove *)
```

Requirements (each is independently enforced):

- **Do not rename or delete** the two fixpoints or the theorem, and do not change
  their types.
- Replace the two `admit` steps with a genuine **structural induction over
  `n`**: the base case is immediate and the step case rewrites with the induction
  hypothesis and the commutativity of `+` (you may import `Lia`). Do not change
  which object is being inducted.
- The finished file must compile with the exact command

  ```
  coqc /app/proof.v
  ```

  and terminate with the **closing proof command** `Qed.` (or `Defined.`).
  After you finish it, record the compile in

  ```
  coqc /app/proof.v > /app/proof-check.log 2>&1
  ```

- The final source may contain **no admitted obligation**: the tokens
  `Admitted`, `admit`, `Oops`, and `admit`-equivalents are forbidden anywhere in
  `/app/proof.v`.

The grader re-runs `coqc /app/proof.v` itself in a scratch area (so a fake,
hand-made `proof-check.log` is worthless), requires that it emits a `.vo`, then
compiles one dependent file in the same directory that does
`Require Import proof.` and derives a corollary from `sumup_eq_sumdown`. If your
module doesn't compile, does not expose those names with those types, or still
carries an admitted obligation, that section fails.

---

## 2. Sympy integrator — `/app/integral.py` and `/app/integral.txt`

Create an executable `/app/integral.py` that **symbolically** integrates over the
unit interval and prints an **exact, simplified closed form** (never a decimal):

```
python3 /app/integral.py [EXPR]
```

Contract:

- With an `EXPR` argument given, the script defines the symbol `x`, builds the
  sympy expression, symbolically integrates it over `x in [0,1]`, **expands and
  simplifies** the result, and prints the simplified closed form on standard
  output (a single line). The printed string must equal what `sympy` itself
  produces — a numeric approximation or an equivalent but **un-simplified**
  alternative fails `simplify(s == reference) == 0`.
- With **no argument**, the fixed client integral is used:

  ```
  EXPR = 4/(1+x**2)
  ```

  whose exact closed form involves the named constant π (`pi`).
- `integral.txt` is that fixed integral's answer:

  ```
  python3 /app/integral.py > /app/integral.txt
  ```

  so `/app/integral.txt` contains `pi` on a single line.
- On an **unparseable / invalid** `EXPR` the script must output a one-line error
  message to standard error and exit with status **2** (it must not hang and
  must not print a bogus numeric onto stdout). The grader feeds deliberately
  malformed strings and requires an orderly nonzero exit.

Allowed imports: the Python standard library plus `sympy`. The grader re-runs
`/app/integral.py` itself on several hidden integrals (a polynomial with a
rational result, a power-like root `sqrt(x)`, a mixed polynomial, and one
malformed expression) and compares your printed closed form to its own freshly
computed sympy result. Hard-coding the visible `4/(1+x**2)` answer will not
satisfy the hidden runs.

---

## 3. R sampler — `/app/sampler.R` and `/app/selftest.log`

Write an R script `/app/sampler.R` that defines **exactly two obliged
functions**, whose names are regular-expression-checked verbatim in the source:

```
willow_sample(n, a = 2)
willow_selftest()
```

- `willow_sample(n, a)` draws `n` uniform samples on `[0,1]`, returns their
  `a`-th-power mean (a Monte-Carlo estimate of `int_0^1 x^a dx = 1/(a+1)`).
  Spell `runif` with the namespace, e.g. `stats::runif`. `n >= 1` must hold;
  `n = 1` must return a finite number.
  Make the run reproducible by seeding inside the function.
- `willow_selftest()` calls `willow_sample`, compares the estimate to
  `1/(a+1)` within tolerance and, on success, prints a line containing the token
  `PASS` and exits status 0; on an out-of-tolerance estimate it prints `FAIL`
  and exits non-zero.

Generate the log by running the self test yourself:

```
cd /app && Rscript -e 'source("/app/sampler.R"); willow_selftest()' > /app/selftest.log 2>&1
```

`/app/selftest.log` must exist, be non-empty, and contain the token `PASS`.

The grader re-loads `/app/sampler.R` in its own R process, asserts both required
function names appear at line-start, that `willow_sample` returns plausible
finite estimates for several `(n, a)` (with `tol`), and re-runs
`willow_selftest()` itself, requiring exit 0 and a `PASS` line. Renaming a
function, or putting it under a different case/spacing so the regex misses it,
fails this section.

---

## 4. LaTeX report — `/app/report.tex`, `/app/report.pdf`, `/app/pdflatex.log`

Author a short LaTeX memo at `/app/report.tex` (caption, a short reprodice
paragraph, an appendix act version). It must compile with

```
cd /app && pdflatex -interaction=nonstopmode -halt-on-error report.tex
```

and produce `/app/report.pdf` and a log file `/app/pdflatex.log` (rename the
produced `report.log`).

The memo must be **free of over-filled box warnings**: `pdflatex.log` must
contain **no** line that matches `Overfull \hbox`. Make this true by writing a
**breakable sentence** and by **synonym substitution**: every place a long
monospaced term would have to appear, write a short, hyphenable synonym instead.

Strict styling/term rules (the grader scans the source and fails when violated):

1. **No over-wide unbreakable token.** Your report must NOT contain the literal
   `electrohydrodynamicelectrohydrodynamicelectrohydrodynamicelectrohydrodynamicelectrohydrodynamic` —
   it is wider than the column and would force TeX to overfill a line.
2. **No long verbatim token.** No `\texttt{...}` (or `{\tt ...}`) whose inner
   text is longer than **24 characters**. Any longer monospaced token trips the
   protection check — replace it with a short synonym or ordinary words.
3. The build must not emit `Overfull \hbox` lines, and the grader also makes a
   **fresh** `pdflatex` run of your `/app/report.tex` in a scratch directory to
   prove reproducibility.

Use the standard `article` class; `geometry`, verbatim-free, no external
packages (all installed). Everything must be self-contained in `/app/report.tex`.

---

## 5. What must NOT be done

- Do not modify anything outside `/app`.
- Do not hand-fabricate the logs or PDFs: produce them by running the tools
  (`coqc`, `python3 /app/integral.py`, `Rscript`, `pdflatex`). A log that a
  stale or hand-written artifact that doesn't match a fresh run is rejected.
- Do not delete or rename the two Coq fixpoints, the Coq theorem, or the two R
  function names.
- There is no hidden data baked into the image for you to read; hidden inputs
  are fed by the grader at verification time.

That's the whole task. Complete each artifact, produce each checked log, and
leave them in `/app`.