#!/bin/bash
# Oracle for item-013-main: bring up the staged c0 build to full reward.
set -euo pipefail

# 1) Diagnose and install the missing toolchain components.
if ! command -v ocamlc >/dev/null 2>&1 || ! command -v coqc >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ocaml coq
fi

cd /app/compcert-src

# 2) Staged build in the documented order.
./configure
make verify
make oextract
make backend

# 3) Self-check against the shipped probe before declaring done.
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
  echo "oracle: staged artifacts missing" >&2
  exit 1
fi
echo "oracle: c0 toolchain build complete"