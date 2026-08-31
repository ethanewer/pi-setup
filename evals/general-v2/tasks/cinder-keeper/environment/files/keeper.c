/*
 * keeper.c — Cinder firmware gate emulator (visible fixture).
 *
 * Reads one line of input into a fixed-size tag buffer that sits
 * immediately adjacent to the `permit` control word in `struct session`.
 * The read is NOT bounds-checked against writes past the tag buffer.
 * When `permit` equals PERMIT_MAGIC the gate opens and prints the
 * guarded unlock code; otherwise it prints LOCKED.
 *
 * Build: gcc -O0 -o keeper keeper.c
 * Run:   ./keeper < payload.bin
 */
#include <stdio.h>
#include <string.h>

#define TAG_LEN 24
#define PERMIT_MAGIC 0x5AFE0DDEu

struct session {
    char tag[TAG_LEN];
    unsigned int permit;
};

int main(void) {
    struct session s;
    memset(&s, 0, sizeof(s));
    fread(s.tag, 1, TAG_LEN + sizeof(unsigned int), stdin);
    if (s.permit == PERMIT_MAGIC) {
        printf("KEEPER_OPEN code=KX-3317\n");
    } else {
        printf("LOCKED\n");
    }
    return 0;
}
