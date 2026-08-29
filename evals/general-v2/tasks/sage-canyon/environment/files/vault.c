/*
 * sage-canyon vault reader.
 *
 * Reads a passphrase line from stdin into a fixed 16-byte buffer that sits
 * immediately before an unsigned "gateway" field in the same struct.  A
 * correct override must (a) fill the whole 16-byte buffer, then (b) lay the
 * fixed magic constant 0x9E1C over the gateway field. Either is enough on its
 * own: an underrun, an over-long/inaccurate write, or any other gate value
 * keeps the branch locked and the guarded token hidden.
 *
 * Build with:  gcc -O0 -o vault vault.c
 * Run with:    ./vault < passphrase-file
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    struct {
        char buf[16];
        unsigned gateway;
    } slot;
    char token[] = "cinq-so-7249-pinole";

    memset(&slot, 0, sizeof slot);
    if (read(0, slot.buf, 4096) < 0) {
        fputs("no input\n", stderr);
        return 2;
    }

    if (slot.gateway == 0x9E1C) {
        printf("TARGET_OPEN token=%s\n", token);
        return 0;
    }
    printf("DENIED\n");
    return 1;
}