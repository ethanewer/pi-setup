#ifndef UTIL_H
#define UTIL_H

#include <stddef.h>
#include <stdio.h>

/*
 * Read one line (without the trailing '\n') into *buf, growing the buffer as
 * needed. On return *buf is NUL-terminated. Returns the number of characters
 * stored (>= 0), or -1 when end of input is reached before any character.
 * The caller owns *buf and must eventually free it.
 */
long read_line(FILE *fh, char **buf, size_t *cap);

#endif /* UTIL_H */
