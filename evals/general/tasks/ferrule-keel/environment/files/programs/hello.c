#include <stdio.h>

int main(void) {
    printf("hello from tcc-built compiler\n");
    printf("sizeof: int=%zu long=%zu ptr=%zu\n",
           sizeof(int), sizeof(long), sizeof(void *));
    printf("'a' as int = %d\n", (int)'a');
    return 0;
}