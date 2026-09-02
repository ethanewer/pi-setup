#!/bin/bash
# Oracle for tasks/larch-terrace (executes-deliverable).
#
# Real work, in order:
#   1) cross-compile the provided C "game" for little-endian MIPS -> /app/game.mips
#   2) author the retargeted gfortran Makefile and BUILD main from the .f90 sources
#   3) author the C/Python polyglot  -> /app/poly.c
#   4) author the arg-max autoregressive sampler (C) and compile it -> /app/app
#   5) author the Scheme metacircular evaluator -> /app/scheme.py
# It never reads /tests.
set -eu

# 1) MIPS cross build (real cross-compile, static so it floats under qemu).
mipsel-linux-gnu-gcc -static -O2 -o /app/game.mips /app/src/game.c

# 2) Fortran: retarget to gfortran and actually build the executable.
cp /solution/Makefile /app/Makefile
cd /app
# Build the gfortran-retargeted executable into /app/main (default target).
make -s -f Makefile
[ -x /app/main ] # oracle must have truly produced /app/main

# 3) Polyglot (valid C AND valid Python 3).
cp /solution/poly.c /app/poly.c

# 4) Arg-max autoregressive sampler in C: author source, then BUILD it.
cp /solution/app.c /app/app.c
gcc -O2 -o /app/app /app/app.c
chmod +x /app/app

# 5) Scheme metacircular evaluator.
cp /solution/scheme.py /app/scheme.py
chmod +x /app/scheme.py

echo "oracle delivered all artifacts"
