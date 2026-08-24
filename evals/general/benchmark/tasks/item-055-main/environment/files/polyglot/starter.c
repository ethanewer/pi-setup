/* starter.c — a correct single-language C implementation of the required
   behavior. Use it as a starting point: your final deliverable is
   /app/polyglot/main.c which must ALSO run as Python 3 and compile as C++.
   Copyright: public domain example for the bench. */
#include <stdio.h>
#include <stdlib.h>

static unsigned long long fib_c(unsigned int n) {
    unsigned long long a = 0, b = 1, t;
    for (unsigned int i = 0; i < n; ++i) {
        t = a + b;
        a = b;
        b = t;
    }
    return a;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "error: expected exactly one argument N (0..93)\n");
        return 1;
    }
    const char *s = argv[1];
    if (s[0] == '\0') {
        fprintf(stderr, "error: N must be a non-negative integer\n");
        return 1;
    }
    for (const char *p = s; *p; ++p) {
        if (*p < '0' || *p > '9') {
            fprintf(stderr, "error: N must be a non-negative integer\n");
            return 1;
        }
    }
    unsigned long n = strtoul(s, NULL, 10);
    if (n > 93) {
        fprintf(stderr, "error: N must be in 0..93\n");
        return 1;
    }
    printf("%llu\n", fib_c((unsigned int)n));
    return 0;
}