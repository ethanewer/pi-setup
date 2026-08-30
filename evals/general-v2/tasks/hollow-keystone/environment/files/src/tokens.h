#ifndef TOKENS_H
#define TOKENS_H

#include <stdio.h>

/*
 * Buffered line reader over `f`. On success returns the number of bytes read
 * (>= 0) and leaves *line pointing at a NUL-terminated buffer (the trailing
 * '\n'/'\r' is stripped). At EOF returns -1.
 */
long read_line(FILE *f, char **line, size_t *cap);

#endif
