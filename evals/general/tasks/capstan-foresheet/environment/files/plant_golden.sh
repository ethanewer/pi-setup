#!/bin/bash
# plant_golden.sh - plants the upstream regression test for the fp.rem bug
# (golden bytes extracted at image build time into /opt/golden/fpa.cpp) into a
# Z3 source tree, exactly as the upstream fix commit registers its new test:
#   1. copies src/test/fpa.cpp (the new test module),
#   2. registers tst_fpa() in src/test/main.cpp's X-macro list (after X(mpf)),
#   3. adds fpa.cpp to the test binary in src/test/CMakeLists.txt (after f2n.cpp).
# Used by build-time smoke, by the verifier, and by the oracle. The caller is
# responsible for restoring the tree (git checkout + rm) if it needs it clean.
set -eu
: "${Z3_SRC:=/app/src}"
GOLDEN=/opt/golden/fpa.cpp
[ -f "$GOLDEN" ] || { echo "plant_golden: $GOLDEN missing" >&2; exit 1; }
cd "$Z3_SRC"
git diff --quiet -- src/test/main.cpp src/test/CMakeLists.txt || {
    echo "plant_golden: src/test/main.cpp or CMakeLists.txt already modified" >&2
    exit 1
}
cp "$GOLDEN" src/test/fpa.cpp
if ! grep -q '^    X(fpa) \\' src/test/main.cpp; then
    sed -i 's/^    X(mpf) \\$/    X(mpf) \\\n    X(fpa) \\/' src/test/main.cpp
fi
if ! grep -q '^  fpa.cpp$' src/test/CMakeLists.txt; then
    sed -i 's/^  f2n.cpp$/  f2n.cpp\n  fpa.cpp/' src/test/CMakeLists.txt
fi
grep -q 'test_rem_subnormal_divisor' src/test/fpa.cpp
echo "plant_golden: fpa regression test planted"