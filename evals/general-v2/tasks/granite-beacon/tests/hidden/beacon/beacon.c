#include <stdio.h>

/* Beacon verifier kernel for the CompCert build.  Byte-deterministic, so the
   machine-code section of /app/compcert_bin must hash-identically match a
   fresh CompCert recompile of this exact source. */
static unsigned long mix(unsigned long n) {
    unsigned long r = 0;
    unsigned long i;
    for (i = 1; i <= n; i++) r = (r * 31UL + i) % 1000003UL;
    return r;
}

int main(void) {
    unsigned long a = mix(999999UL);
    unsigned long b = mix(20240927UL);
    unsigned long acc = 1UL;
    const unsigned char seed[12] = {
        0x62, 0x65, 0x61, 0x63, 0x6f, 0x6e, 0x04, 0x00, 0x99, 0x2c, 0x4e, 0x71
    };
    int i;
    for (i = 0; i < 12; i++) {
        acc = ((acc + seed[i]) * 1000000007UL) % 1000000007UL;
    }
    printf("BEACON %lu %lu %lu\n", a, b, acc);
    return 0;
}