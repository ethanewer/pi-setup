#include <stdio.h>
#include <assert.h>

int normalize(int x){
    assert(x >= 0);                /* debug-only guard; fails for x < 0 */
    return (x < 0) ? 0 : x;        /* clamp negatives to 0 */
}

int main(void){
    int input = -7;
    int out = normalize(input);
    printf("out=%d\n", out);
    return 0;
}
