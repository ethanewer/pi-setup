/*
 * item-075-main: a deliberately vulnerable 64-bit x86-64 ELF.
 *
 * capture() reads up to 255 bytes into a 64-byte stack buffer with read().
 * There is no stack protector, no PIE, and no fortify.  win() is a normal
 * function that prints the secret and writes /app/flag.txt.
 *
 * Compiled with: gcc -O0 -g -fno-stack-protector -no-pie
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

void win(void) {
    FILE *f = fopen("/app/flag.txt", "w");
    if (f) {
        fprintf(f, "PWNED_ITEM_075\n");
        fclose(f);
    }
    printf("ACCESS GRANTED\n");
    exit(0);
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