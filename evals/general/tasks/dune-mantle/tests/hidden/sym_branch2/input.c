#include <stdlib.h>
/* 2-outcome integer function. The symbolic engine must produce concrete tests
   for both branches. */
int target(int a, int b) {
    int s = (a * 3) - (b * 2);
    if (s > 6) return 44;
    return 15;
}
int main(int argc, char **argv) {
    return target(atoi(argv[1]), atoi(argv[2]));
}
