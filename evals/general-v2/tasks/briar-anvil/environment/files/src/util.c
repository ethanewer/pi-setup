#include "util.h"

#include <stdlib.h>

long read_line(FILE *fh, char **buf, size_t *cap)
{
    size_t len = 0;
    int c;

    if (*buf == NULL) {
        *cap = 128;
        *buf = malloc(*cap);
        if (*buf == NULL) {
            return -1;
        }
    }

    c = fgetc(fh);
    if (c == EOF) {
        return -1;
    }

    while (c != EOF && c != '\n') {
        if (len + 2 > *cap) {
            size_t ncap = *cap * 2;
            char *nbuf = realloc(*buf, ncap);
            if (nbuf == NULL) {
                return -1;
            }
            *buf = nbuf;
            *cap = ncap;
        }
        (*buf)[len++] = (char)c;
        c = fgetc(fh);
    }

    (*buf)[len] = '\0';
    return (long)len;
}
