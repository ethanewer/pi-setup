#include <stdio.h>

/* Small kernel compiled at several distinct -O levels for the size table. */
static double wobble(int k) {
    double a = 1.0;
    int i;
    for (i = 1; i <= k; i++) a = a * (double)i + 0.5;
    return a;
}

int main(int argc, char **argv) {
    long acc = 0;
    int i;
    for (i = 0; i < 512; i++) acc += (long)wobble((i % 17) + 2);
    printf("kern %ld\n", acc < 0 ? -acc : acc);
    return 0;
}