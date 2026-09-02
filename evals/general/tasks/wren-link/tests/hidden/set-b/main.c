#include <stdio.h>

int a_seq(int x);
int c_seq(int x);

int main(void) {
    printf("seq=%d\n", c_seq(4));
    printf("a=%d\n", a_seq(100));
    return 0;
}
