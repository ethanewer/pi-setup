#!/bin/bash
# dune-mantle oracle: build everything on /app by DOING the work.
set -euo pipefail
cd /app

# 1. The quantifier/weighted/boarding solver.
cp /solution/impl/solve.py /app/solve.py
chmod +x /app/solve.py

# 2. The symbolic execution engine, globally invocable on PATH.
cp /solution/impl/symxe.py /usr/local/bin/symxe
chmod +x /usr/local/bin/symxe
/usr/local/bin/symxe --version >/dev/null

# 3. Engine run against the visible bitcode seed (both branches).
mkdir -p /app/work
clang -emit-llvm -c /app/seed/classify.c -o /app/work/classify.bc
/usr/local/bin/symxe run /app/work/classify.bc > /app/work/classify.symx

# 4. Coq: compile the hand-proven source to a compiled proof object.
mkdir -p /app/cert
cp /solution/impl/astral.v /app/cert/astral.v
( cd /app/cert && coqc astral.v )

# 5. Produce /app/answer.json by running the real computations.
/usr/bin/python3 /solution/impl/make_answer.py

echo "ORACLE_OK"