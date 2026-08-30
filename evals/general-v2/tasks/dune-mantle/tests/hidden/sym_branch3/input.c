#include <stdlib.h>
/* 3-outcome integer function. The engine must cover every reachable outcome. */
int target(int a) {
    int v = a - 4;
    if (v > 7) return 19;
    if (v > -3) return 26;
    return 9;
}
int main(int argc, char **argv) {
    return target(atoi(argv[1]));
}
