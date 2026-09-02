#include <stdio.h>

int vc_base(int x);
int vc_trim(int x);

int main(void) {
    printf("trim=%d\n", vc_trim(11));
    printf("base=%d\n", vc_base(3));
    return 0;
}
