#define _GNU_SOURCE
#include "tokens.h"

#include <stdlib.h>

long read_line(FILE *f, char **line, size_t *cap) {
    long n = getline(line, cap, f);
    if (n <= 0) {
        return -1;
    }
    while (n > 0 && ((*line)[n - 1] == '\n' || (*line)[n - 1] == '\r')) {
        (*line)[--n] = '\0';
    }
    return n;
}
