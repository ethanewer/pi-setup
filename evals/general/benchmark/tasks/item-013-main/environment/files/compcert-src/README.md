# compcert-src — staged "certified C0" toolchain build

This tree is a snapshot of the staged source build of a CompCert-3.13.1-style
"certified C" front-end named **c0**. It is deliberately not pre-built: bringing
it up requires running a staged `configure` then `make` sequence, and gives you
practice following a multi-stage build and diagnosing missing compiler /
toolchain components on the host.

## Layout

```
compcert-src/
  configure          autoconf-style bootstrap; must run first
  Makefile           staged build chain
  cert/cert.v        Coq certificate record (compiled by the 'verify' stage)
  src/stamp.ml       tiny OCaml module (compiled by the 'oextract' stage)
  src/ccomp.c        the c0 compiler backend + documented semantics
  probe/sample.c     a sample c0 program
  probe/sample.out   expected output for probe/sample.c
  build/             generated at build time (cfg file, deploy header, output)
```

## Required toolchain

This build needs a C compiler (`gcc`) and the OCaml + Coq toolchain binaries
`ocamlc` and `coqc`. The prebuilt image ships only `gcc` and `make`. The
`configure` probe checks for `gcc`, `ocamlc`, and `coqc`, and fails loudly with
the name of any component it cannot find on the host.

On a stock Ubuntu 24.04 host the missing components are installed by:

```
apt-get install -y ocaml coq
```

## Host ABI / architecture constraint

`configure` inspects the host CPU (via `uname -m`) and refuses architectures it
does not recognize. On every supported host the intended **wordsize is 64**.
The deployment header line printed at the top of every `c0` output file is
`; wordsize <N>`, where `<N>` is the configured wordsize from the generated
`build/deploy.mk`. The hidden grader expects this header to say `; wordsize 64`.
If the build is configured to another wordsize, grading fails to match.

## Staged build

Run in this order (or just `make all`):

```
make all              # stage 0 configure, stage 1 verify, stage 2 oextract, stage 3 backend
```

Stages, individually:

```
./configure           # stage 0: probe + generate build/deploy.mk and build/cfg.mk
make verify           # stage 1: coqc  cert/cert.v   -> build/cert.checked
make oextract         # stage 2: ocamlc src/stamp.ml -> build/oextract.checked
make backend          # stage 3: gcc    -> build/c0
```

If a stage fails, read its output. The two tools you almost certainly must
install first are named by `configure`.

## Using the produced c0

`build/c0` is a CLI translating a small source file into textual output:

```
./build/c0 <input-file> <output-file>
```

It first writes the deployment header line `; wordsize <N>`, then, for each
`put E;` statement in the input program (in order), writes one line containing
the decimal value of expression `E`. Read `src/ccomp.c` for the exact language
grammar and value semantics.

## Self-check (required before finishing)

```
./build/c0 probe/sample.c /tmp/probe.actual
diff -u /tmp/probe.actual probe/sample.out
```

If the diff is non-empty, re-read `src/ccomp.c` (it documents its own language
and its *edit boundary*) and re-inspect the build log. Do not delete or rename
any staged artifacts; the grader counts them.