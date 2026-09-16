# Ferrule-berth: build and drive a real SAT solver

## Context

`/app/src` is a shallow clone of the CaDiCaL SAT solver (arminbiere/cadical),
pinned to commit `c60730422e758ef1cebe7aeddf2dda31c996bf04` (version 3.0.1).
It is a real, production C++ solver with a `configure && make` build. The
image has already run that build once, so recompiling is cheap; you must do
it anyway.

Your job is to build and then **drive** the solver: write a command-line
driver that uses CaDiCaL correctly on Boolean formulas in two input formats,
including formulas that have no solution, and that produces, for every
unsatisfiable plain formula, a proof of unsatisfiability that the solver's
own machinery accepts.

There is no network in this container. Everything you need is on disk.

## What is on disk

- `/app/src` – the CaDiCaL source tree (do not modify it; you only build it).
- `/app/cases/` – sample inputs of every shape you must support:
  - `simple-sat.cnf`         satisfiable plain DIMACS CNF
  - `simple-unsat.cnf`       unsatisfiable plain DIMACS CNF
  - `incremental-sat.icnf`   incremental input with assumption cubes (satisfiable)
  - `incremental-unsat.icnf` incremental input with assumption cubes (unsatisfiable)

Read `cadical --help` (and the source under `/app/src/src/` if you like)
before deciding how to drive it. The evidence lines that start with `s `
and `v ` printed on stdout are the contract with the outside world. Exit
status is also meaningful (10 vs 20).

## Deliverables

Create exactly two files (plus anything you put under `/app/work/`):

1. `/app/cadical` – the solver binary, produced by the project's own build
   system from `/app/src` and the pinned source. Build it yourself: the
   image deliberately does not contain a finished binary.

2. `/app/driver.sh` – an executable Bash script with this exact interface:

```
/app/driver.sh <input> <outdir>
```

- `<input>` is a formula in one of two formats, distinguished by its header:
  - plain DIMACS CNF (`p cnf <vars> <clauses>`)
  - incremental CNF (`p inccnf`) – the same clauses followed by one or more
    assumption *cubes* (lines starting with `a`). The solver solves the
    formula jointly with each cube; the overall result depends on every cube.
- `<outdir>` must be created by the driver if missing.
- On success the driver exits 0 and writes:
  - `<outdir>/verdict` – exactly one line: `s SATISFIABLE` or
    `s UNSATISFIABLE` (a trailing newline is fine),
  - `<outdir>/model`      – for a satisfiable input, the witness model as
    printed by the solver (its `v ...` lines),
  - `<outdir>/proof.lrat` – for an **unsatisfiable plain DIMACS CNF** input,
    the solver's own LRAT proof of unsatisfiability, in the human-readable
    ASCII encoding (the bit-for-bit derivation the solver emits).
    No proof is required for incremental inputs.

The driver must run the solver you built at `/app/cadical` for every solve;
it must not contain or call a second, independent solver. It may re-run the
build (`cd /app/src && make -j1` followed by copying the result to
`/app/cadical`) if the binary is missing; do not re-run `./configure`.

## Requirements, in the order a grader checks them

1. `/app/cadical` is really CaDiCaL built from the pinned source. A run of
   `/app/cadical --version` must identify it as version 3.0.1 of the pinned
   commit.
2. `/app/driver.sh` invokes `/app/cadical` and produces the files above.
3. Every verdict must be correct: a model you report for a satisfiable input
   must actually satisfy every clause of that input, and an unsatisfiable
   input must never be reported satisfiable.
4. The two input formats must both be driven correctly. In the incremental
   format the *cubes are part of the question*: an input is satisfiable only
   if some cube is jointly satisfiable with the clause set, and the reported
   verdict must be `s UNSATISFIABLE` exactly when every cube is unsatisfiable
   jointly with the clauses. Beware that the plain clause set alone can be
   satisfiable while the cubes make the whole question unsatisfiable.
5. Every unsatisfiable plain DIMACS CNF must come with a valid LRAT proof in
   `<outdir>/proof.lrat`, and the proof must be one the project's own proof
   checker accepts. CaDiCaL ships its proof checker inside the solver: while
   it runs with proof checking enabled it validates every derived clause
   against the formula and aborts on the first invalid step. Make sure the
   run that emits the proof has that checking enabled, and convince yourself
   the emitted trail is a real derivation (what is the last derived clause of
   the proof?).

## Notes

- cpus = 1. Keep invocations sequential.
- Test against `/app/cases/` before you finish; the hidden inputs differ from
  them but exercise exactly these four situations: satisfiable plain,
  unsatisfiable plain, satisfiable incremental, unsatisfiable incremental.
- Do not modify `/app/src` or `/app/cases`; they belong to the evaluation.