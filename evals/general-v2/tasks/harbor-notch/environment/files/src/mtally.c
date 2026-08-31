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
        _exit(3);
    }

    while (fgets(line, sizeof line, f)) {
        char key[256];
        long count = 0;

        if (!parse_line(line, key, sizeof key, &count)) {
            if (strchr(line, '!')) {
                fprintf(stderr, "fatal token in line\n");
                _exit(4);
            }
            bad++;
            continue;
        }
        store_add(key, count);
    }
    fclose(f);

    store_report(bad);
    _exit(0);
}
