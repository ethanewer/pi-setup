#include <stdio.h>

static unsigned int gcd(unsigned int a, unsigned int b) {
    while (b) {
        unsigned int t = a % b;
        a = b;
        b = t;
    }
    return a;
}

int main(void) {
    printf("gcd(1071,462)=%u\n", gcd(1071, 462));
    unsigned long p = 1;
    for (int i = 0; i < 20; i++) p *= 3u;
    printf("3^20=%lu\n", p);
    printf("wrap=%u signed=%d\n", 0u - 1u, (int)(0u - 1u));
    printf("ternary=%d\n", gcd(12, 8) > 4 ? 1000 : -1000);
    return 0;
}