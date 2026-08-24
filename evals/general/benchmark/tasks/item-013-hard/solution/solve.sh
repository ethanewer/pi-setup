#!/bin/bash
# Oracle for item-013-hard: repair and bring up the hardened staged build.
set -euo pipefail

# 1) Diagnose and install missing toolchain components.
if ! command -v ocamlc >/dev/null 2>&1 || ! command -v coqc >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ocaml coq
fi

cd /app/cc-src

# 2) Clear the planted benign defects (the unused-variable line the README
#    names, plus the unchecked fread return that -Werror=unused-result flags).
python3 - <<'PY'
lines = open("src/ccomp.c").read().split("\n")
lines = [l for l in lines if "orphan" not in l and "unused sentinel" not in l]
src = "\n".join(lines)
src = src.replace("fread(buf, 1, (size_t)sz, in);",
                  "(void)fread(buf, 1, (size_t)sz, in);")
open("src/ccomp.c", "w").write(src)
PY

# 3) Staged build in the documented order. configure regenerates the
#    authoritative (wordsize 64) machine.h and fails if tools are missing.
./configure
make verify
make oextract
make backend

# 4) Self-check against the shipped probe; header must say wordsize 64.
if [ ! -f build/c0 ]; then
  echo "oracle: build/c0 missing" >&2
  exit 1
fi
./build/c0 probe/sample.c /tmp/probe.actual
if ! diff -u /tmp/probe.actual probe/sample.out >/dev/null; then
  echo "oracle: probe mismatch" >&2
  exit 1
fi
if [ ! -f build/cert.checked ] || [ ! -f build/oextract.checked ]; then
  echo "oracle: certified artifacts missing" >&2
  exit 1
fi
echo "oracle: hardened c0 build complete"