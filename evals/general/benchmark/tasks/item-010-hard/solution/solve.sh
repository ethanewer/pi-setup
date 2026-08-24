#!/bin/bash
# Oracle solution for item-010: synthesize two combinational netlists.
set -euo pipefail

cat > /app/build.c <<'C_EOF'
#include <stdio.h>

static unsigned long long gid = 0;
static unsigned long long MASK = 0;

/* emit a 1-operand gate: op id a */
static unsigned long long g1(const char *op, unsigned long long a){
    printf("%s %llu %llu\n", op, gid, a);
    return gid++;
}
/* 2-operand gate */
static unsigned long long g2(const char *op, unsigned long long a, unsigned long long b){
    printf("%s %llu %llu %llu\n", op, gid, a, b);
    return gid++;
}
/* 3-operand gate */
static unsigned long long g3(const char *op, unsigned long long a, unsigned long long b, unsigned long long c){
    printf("%s %llu %llu %llu %llu\n", op, gid, a, b, c);
    return gid++;
}

/* emit C constant gate, masked to width */
static unsigned long long cst(unsigned long long v){
    return g1("C", v & MASK);
}

static void gen_sqrt32(void){
    int W = 32;
    MASK = (W == 64) ? ~0ULL : ((1ULL << W) - 1);
    gid = 0;
    printf("WIDTH %d\n", W);
    unsigned long long x  = g1("IN", 0);           /* input word 0 */
    unsigned long long c0 = cst(0);
    unsigned long long c1 = cst(1);
    unsigned long long q  = c0;
    int i;
    for (i = 15; i >= 0; i--) {
        unsigned long long b  = cst(1ULL << i);
        unsigned long long t  = g2("ADD", q, b);
        unsigned long long p  = g2("MUL", t, t);
        unsigned long long lt = g2("LT", x, p);       /* 1 if x < t*t */
        unsigned long long keep = g2("EQ", lt, c0);   /* 1 if x >= t*t */
        q = g3("IF", keep, t, q);
    }
    printf("OUT 0 %llu\n", q);
}

static void gen_fib64(void){
    int W = 64;
    unsigned long long K = 64;
    MASK = ~0ULL; /* 2^64 - 1 */
    gid = 0;
    printf("WIDTH %d\n", W);
    unsigned long long k = g1("IN", 0);
    unsigned long long c0 = cst(0);
    unsigned long long c1 = cst(1);
    unsigned long long f[K+1];
    f[0] = c0;
    f[1] = c1;
    unsigned long long i;
    for (i = 2; i <= K; i++) {
        f[i] = g2("ADD", f[i-1], f[i-2]);
    }
    unsigned long long res = f[K];
    for (i = K; i >= 1; i--) {
        unsigned long long ci = cst(i);
        unsigned long long eq = g2("EQ", k, ci);
        res = g3("IF", eq, f[i], res);
    }
    /* handle k == 0 explicitly (loop above started at i=K down to 1) */
    {
        unsigned long long c0b = cst(0);
        unsigned long long eq  = g2("EQ", k, c0b);
        res = g3("IF", eq, f[0], res);
    }
    printf("OUT 0 %llu\n", res);
}

int main(void){
    if (freopen("/app/sqrt_32.ng", "w", stdout) == NULL) return 1;
    gen_sqrt32();
    if (freopen("/app/fib_64.ng", "w", stdout) == NULL) return 1;
    gen_fib64();
    return 0;
}
C_EOF

gcc -O2 -o /app/build /app/build.c
/app/build