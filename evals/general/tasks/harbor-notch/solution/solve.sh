#!/bin/bash
# Oracle for harbor-notch: repair /app/src/mtally.c so every exit path goes
# through main's normal return and the atexit-registered global destructor
# runs (no _exit short-circuits, no leaks). Then build /app/src/mtally.
# Never reads /tests.
set -eu

cat > /app/src/mtally.c <<'C'
/* mtally - tally KEY=COUNT lines from a metrics file.
 *
 * Valid line: KEY=COUNT where KEY is [A-Za-z][A-Za-z0-9_]* and COUNT is a
 * non-empty run of decimal digits. Everything else is malformed and must be
 * counted in the bad-line total; processing continues to EOF.
 *
 * Lifecycle contract: store_init() registers the global-registry destructor
 * with atexit(); every exit path must go through main's normal return so the
 * destructor runs and the process leaves zero definite leaks.
 */
#include "store.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int parse_line(const char *line, char *key, size_t keycap, long *count)
{
    const char *p = line;
    size_t k = 0;
    long v = 0;

    if (!isalpha((unsigned char)*p)) {
        return 0;
    }
    while (isalnum((unsigned char)*p) || *p == '_') {
        if (k + 1 >= keycap) {
            return 0;
        }
        key[k++] = *p++;
    }
    key[k] = '\0';
    if (*p != '=') {
        return 0;
    }
    p++;
    if (!isdigit((unsigned char)*p)) {
        return 0;
    }
    while (isdigit((unsigned char)*p)) {
        v = v * 10 + (*p - '0');
        p++;
    }
    *count = v;
    if (*p == '\n' || *p == '\0') {
        return 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    long bad = 0;
    FILE *f;
    char line[1024];

    if (argc != 2) {
        fprintf(stderr, "usage: mtally <file>\n");
        return 2;
    }

    store_init();

    f = fopen(argv[1], "r");
    if (!f) {
        fprintf(stderr, "cannot open %s\n", argv[1]);
        return 3; /* normal exit path: the atexit destructor still runs */
    }

    while (fgets(line, sizeof line, f)) {
        char key[256];
        long count = 0;

        if (!parse_line(line, key, sizeof key, &count)) {
            /* A malformed line (including any line containing '!') is just
             * counted; processing continues to EOF. */
            bad++;
            continue;
        }
        store_add(key, count);
    }
    fclose(f);

    store_report(bad);
    return 0; /* normal exit path: the atexit destructor frees the registry */
}
C

make -C /app/src >/dev/null

# Self-check: visible sample and a leak check through the normal exit path.
/app/src/mtally /app/data/sample.tly
valgrind --quiet --error-exitcode=42 --leak-check=full \
    --errors-for-leak-kinds=definite,possible \
    /app/src/mtally /app/data/sample.tly > /dev/null

echo "solve.sh done -> /app/src/mtally.c and /app/src/mtally"
ls -l /app/src/mtally.c /app/src/mtally
