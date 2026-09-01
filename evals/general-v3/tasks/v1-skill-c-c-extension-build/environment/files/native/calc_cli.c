#include <stdio.h>
#include <stdlib.h>
#include "libcalc.h"

int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: calc_cli <a> <b>\n");
        return 2;
    }
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    printf("add=%d sub=%d\n", calc_add(a, b), calc_sub(a, b));
    return 0;
}
