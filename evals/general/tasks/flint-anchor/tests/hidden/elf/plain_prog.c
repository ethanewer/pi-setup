/* A distinct flint utility used as an extra ELF sample for the section &
 * symbol-string resolver. Compiled at verify time with -no-pie so it carries
 * .text/.data/.rodata/.symtab/.strtab with a non-trivial set of symbols. */
#include <stdio.h>

static long scale(long v) { return v * 1000L; }

const char hello[] = "flint-static-hello";

long helper(long a, long b) {
    static unsigned int counter = 0;
    counter += 1;
    return scale(a) + b + (long)counter;
}

int main(int argc, char **argv) {
    long total = 0;
    for (int i = 1; i < argc; i++) {
        total += helper(i, (long)argv[i][0]);
    }
    printf("%ld %s\n", total, hello);
    return 0;
}
