#include <stdio.h>

int global_base = 7;

int triple(int k) { return k * 3 + global_base; }

int main(void) {
    printf("%d\n", triple(4));
    return 0;
}