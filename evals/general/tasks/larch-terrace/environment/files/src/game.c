/* The additive game: read one integer n and print the running total 1..n.
   A deliberately tiny, deterministic "game" used to exercise the little-endian
   MIPS cross toolchain (built with mipsel-linux-gnu-gcc and run via qemu). */
#include <stdio.h>

int main(void) {
    int n, i, s = 0;
    if (scanf("%d", &n) != 1) return 1;
    for (i = 1; i <= n; i++) s += i;
    printf("%d\n", s);
    return 0;
}
