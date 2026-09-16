#!/bin/bash
# plant_golden.sh - plants the project's own regression test for the fp.fma
# binary16 mis-rounding bug into a Z3 source tree: it replaces
# src/test/smt_context.cpp with the fix-commit version of the file (golden
# bytes extracted at image build time into /opt/golden/smt_context.cpp; that
# version keeps every pre-existing test in the module and adds the
# fused-multiply-add regression block).
#
# Used by the build-time smoke step, by the verifier, and by the oracle. The
# caller is responsible for restoring the tree (`git checkout --
# src/test/smt_context.cpp`) if it needs it clean afterwards.
set -eu
: "${Z3_SRC:=/app/src}"
GOLDEN=/opt/golden/smt_context.cpp
[ -f "$GOLDEN" ] || { echo "plant_golden: $GOLDEN missing" >&2; exit 1; }
cd "$Z3_SRC"
git diff --quiet -- src/test/smt_context.cpp || {
    echo "plant_golden: src/test/smt_context.cpp already modified" >&2
    exit 1
}
grep -q "fp.fma RNE x y x" "$GOLDEN" || {
    echo "plant_golden: golden file does not contain the regression query" >&2
    exit 1
}
cp "$GOLDEN" src/test/smt_context.cpp
grep -q "fp.fma RNE x y x" src/test/smt_context.cpp
echo "plant_golden: smt_context regression block planted"