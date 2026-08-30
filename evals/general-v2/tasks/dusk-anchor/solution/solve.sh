#!/bin/bash
# Oracle for dusk-anchor: implement the vellum transform per /app/vellum-spec.txt
# as a standalone C program, build it statically, and produce the proof digest.
# Never reads /tests.
set -eu

mkdir -p /app/dusk

# ---- 1. The deliverable source (this IS the work).
cat > /app/dusk/app.c <<'C'
#include <stdio.h>
#include <stdlib.h>

/* vellum transform: mirror the input, cascade with an output-fed key,
 * then append the XOR trailer. stdin -> stdout, binary-exact. */
int main(void) {
    size_t cap = 4096, n = 0;
    unsigned char *buf = (unsigned char *)malloc(cap);
    if (buf == NULL) return 1;
    int c;
    while ((c = getchar()) != EOF) {
        if (n == cap) {
            cap *= 2;
            unsigned char *t = (unsigned char *)realloc(buf, cap);
            if (t == NULL) { free(buf); return 1; }
            buf = t;
        }
        buf[n++] = (unsigned char)c;
    }
    unsigned int k = 0x5Du;
    unsigned int trailer = 0u;
    size_t i = n;
    while (i-- > 0) {
        unsigned int o = (unsigned int)buf[i] ^ k;
        putchar((int)o);
        trailer ^= o;
        k = (k + o + 0x33u) & 0xFFu;
    }
    putchar((int)trailer);
    free(buf);
    return 0;
}
C

# ---- 2. The deliverable Makefile (default target builds a static `app`).
cat > /app/dusk/Makefile <<'M'
CC      = gcc
CFLAGS  = -O2 -Wall -Wextra
LDFLAGS = -static

app: app.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o app app.c

clean:
	rm -f app
M

# ---- 3. Build the statically linked binary.
make -C /app/dusk

# ---- 4. Proof digest: run the built binary over the seed fixture.
DIGEST="$(/app/dusk/app < /app/seed.bin | sha256sum | awk '{print $1}')"
printf '%s\n' "$DIGEST" > /app/proof.txt

echo "solve.sh done"
ls -l /app/dusk/app.c /app/dusk/Makefile /app/dusk/app /app/proof.txt
