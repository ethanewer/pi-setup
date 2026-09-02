#!/bin/bash
# Real oracle for flint-anchor.
# Produces every deliverable by doing the work: installs each reference
# program/source into /app, then RUNS them (builds the IR executable and
# runs it, sweeps a sample heap bitmap, compiles the C++11 header strictly,
# runs the grouper and resolver) so the deliverables are genuinely produced.
# Never reads /tests and never cats a precomputed answer.
set -eu

S=/solution

# --- deliverable 1: call-site grouper -------------------------------------
cp "$S/callsites.py" /app/callsites.py
chmod +x /app/callsites.py
python3 /app/callsites.py /app/samples/traces.txt > /dev/null   # run it

# --- deliverable 2: corrected GC sweeping source --------------------------
cp "$S/sweep_fixed.c" /app/vm/sweep.c
rm -f /app/vm/sweep_fixed.c
# compile-check the corrected sweep path and exercise it on a sample bitmap
cat > /tmp/sweep_selfcheck.c <<'EOF'
#include "sweep.h"
#include <stdio.h>
int main(void){
    unsigned char live[16] = {1,0,0,1,0,0,0,1,0,1,1,0,0,0,0,0};
    run_t out[32];
    int n = sweep(live, 16, out, 32);
    /* expected runs: [1..3),[4..7),[8..9),[11..16) -> 4 runs */
    if (n != 4 || out[3].start!=11 || out[3].len!=5) { fprintf(stderr,"sweep selfcheck failed\n"); return 1; }
    printf("sweep-ok runs=%d\n", n);
    return 0;
}
EOF
gcc -I/app/vm -o /tmp/sweep_selfcheck /tmp/sweep_selfcheck.c /app/vm/sweep.c
/tmp/sweep_selfcheck > /dev/null

# --- deliverable 3: C++11 constexpr port ----------------------------------
cp "$S/Sum_fixed.hpp" /app/math/Sum.hpp
cat > /tmp/sum_selfcheck.cpp <<'EOF'
#include "/app/math/Sum.hpp"
static_assert(Sum<1,2,3>::value == 6, "");
static_assert(Sum<>::value == 0, "");
static_assert(Sum<9>::value == 9, "");
int main(){ return 0; }
EOF
g++ -std=c++11 -Wall -Wextra -pedantic-errors -Werror -o /tmp/sum_selfcheck /tmp/sum_selfcheck.cpp

# --- deliverable 4: executable built from the emitted IR ------------------
cp "$S/mkbin.py" /app/mkbin.py
chmod +x /app/mkbin.py
mkdir -p /app/bin
gcc -shared -fPIC -o /app/bin/libcore.so /app/lib/core.c          # build lib
python3 /app/mkbin.py /app/ir/emit.s /app/bin/libcore.so /app/bin/flint_app
/app/bin/flint_app > /tmp/flint_app.out                           # run it
[ "$(cat /tmp/flint_app.out)" = "46" ] || { echo "flint_app validation failed" >&2; exit 1; }

# --- deliverable 5: section & symbol string resolver ----------------------
cp "$S/sections.py" /app/sections.py
chmod +x /app/sections.py
python3 /app/sections.py /app/bin/flint_app > /dev/null           # run it

echo "flint-anchor oracle OK"
