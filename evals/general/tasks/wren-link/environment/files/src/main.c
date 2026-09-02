// main.c — Skerry demo harness. Read-only; build it yourself and link it
// against the combined plugin module.
#include <stdio.h>

int sk_gain(int x);
int sk_mix(int a, int b);
int sk_shape(int x);
int sk_limit(int x);

int main(void) {
    printf("gain=%d\n", sk_gain(5));
    printf("mix=%d\n", sk_mix(3, 4));
    printf("shape=%d\n", sk_shape(10));
    printf("limit=%d\n", sk_limit(29));
    return 0;
}
