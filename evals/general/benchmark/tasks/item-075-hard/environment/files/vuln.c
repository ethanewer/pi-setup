/*
 * item-075-hard: a deliberately vulnerable 64-bit x86-64 ELF.
 *
 * Like the medium variant: capture() reads 255 bytes into a 64-byte stack
 * buffer, no canary, no PIE.  The twist: win() only hands out the credential
 * when its argument equals the magic constant 0xC0FFEE11 (first integer
 * argument on x86-64 arrives in RDI).  Reaching win() is not enough - you must
 * also place the constant in RDI, then return to win().  That is a classic
 * two-gadget ROP chain (pop rdi; ret) + (ret).
 *
 * Two unsed helper functions plant the gadget bytes we need:
 *   plant_poprdi_ret()  -> emits .byte 0x5f, 0xc3   (pop %rdi; ret)
 *   plant_ret()         -> emits .byte 0xc3         (ret)
 * They are kept in .text by __attribute__((used)).
 *
 * Compiled with: gcc -O0 -g -fno-stack-protector -no-pie
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

__attribute__((used, noinline)) static void plant_poprdi_ret(void) {
    asm volatile(".byte 0x5f, 0xc3");
}

__attribute__((used, noinline)) static void plant_ret(void) {
    asm volatile(".byte 0xc3");
}

void win(unsigned long code) {
    if (code == 0xC0FFEE11UL) {
        FILE *f = fopen("/app/flag.txt", "w");
        if (f) {
            fprintf(f, "PWNED_HARD_075\n");
            fclose(f);
        }
        printf("ACCESS GRANTED code=0x%lx\n", code);
        exit(0);
    }
    printf("wrong code 0x%lx\n", code);
    exit(1);
}

static void capture(void) {
    char buf[64];
    printf("Enter your input:\n");
    ssize_t n = read(0, buf, 255);   /* overflow: 255 bytes into 64 */
    if (n < 0) n = 0;
    buf[n] = 0;
    printf("got %zd bytes\n", n);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    capture();
    printf("boom\n");
    return 0;
}