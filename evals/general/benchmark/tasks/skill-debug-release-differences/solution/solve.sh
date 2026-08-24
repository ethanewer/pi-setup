#!/bin/bash
set -euo pipefail
cat > /app/calc.c <<'CF'
#include <stdio.h>
#include <assert.h>

int normalize(int x){
    if (x < 0) x = 0;        /* clamp negatives to 0 in both build modes */
    assert(x >= 0);          /* invariant now always holds */
    return x;
}

int main(void){
    int input = -7;
    int out = normalize(input);
    printf("out=%d\n", out);
    return 0;
}
CF
gcc -Wall /app/calc.c -o /tmp/run_dbg && /tmp/run_dbg > /app/debug.out
gcc -DNDEBUG /app/calc.c -o /tmp/run_rel && /tmp/run_rel > /app/release.out
