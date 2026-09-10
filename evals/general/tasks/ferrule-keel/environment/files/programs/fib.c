#include <stdio.h>

static unsigned long fib(unsigned int n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    printf("fib(30)=%lu\n", fib(30));
    printf("fib(0..8)=");
    for (unsigned int i = 0; i < 9; i++) {
        printf(i ? ",%lu" : "%lu", fib(i));
    }
    printf("\n");
    return 0;
}