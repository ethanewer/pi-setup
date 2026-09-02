#!/bin/bash
# Oracle for kiln-anchor: author the C source, compile it to /app/dist,
# install it for bare-name PATH invocation, and smoke-test on the visible log.
# Never reads /tests.
set -eu

mkdir -p /app/src /app/dist

cp /dev/stdin /app/src/kilnstat.c <<'EOF'
/* kilnstat — Kilnwatch gauge log reducer.
 *
 * usage: kilnstat <logfile>
 * Lines: blank/whitespace-only ignored; leading-# comments ignored; other
 * lines must be exactly "<HH:MM> <temperature>"; otherwise malformed.
 * HH 00-23, MM 00-59 (strict two digits). Temperature matches
 * [+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)? implemented as a
 * character-set filter plus strtod full-consumption.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int valid_time(const char *s) {
    if (strlen(s) != 5 || s[2] != ':') return 0;
    for (int i = 0; i < 5; i++) {
        if (i == 2) continue;
        if (s[i] < '0' || s[i] > '9') return 0;
    }
    int hh = (s[0] - '0') * 10 + (s[1] - '0');
    int mm = (s[3] - '0') * 10 + (s[4] - '0');
    return hh <= 23 && mm <= 59;
}

static int valid_num(const char *s, double *out) {
    static const char ok[] = "0123456789.eE+-";
    size_t n = strlen(s);
    if (n == 0) return 0;
    for (size_t i = 0; i < n; i++)
        if (!strchr(ok, s[i])) return 0;
    char *end = NULL;
    double v = strtod(s, &end);
    if (end != s + n || end == s) return 0;
    *out = v;
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: kilnstat <logfile>\n");
        return 2;
    }
    FILE *fh = fopen(argv[1], "r");
    if (!fh) {
        fprintf(stderr, "kilnstat: cannot open %s\n", argv[1]);
        return 1;
    }
    char line[4096];
    long n = 0, malformed = 0;
    double mn = 0.0, mx = 0.0, sum = 0.0;
    while (fgets(line, sizeof line, fh)) {
        char *p = line;
        while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
        if (*p == '\0') continue;          /* blank */
        if (*p == '#') continue;           /* comment */
        char *tok1 = strtok(p, " \t\r\n");
        char *tok2 = (tok1 != NULL) ? strtok(NULL, " \t\r\n") : NULL;
        char *tok3 = (tok2 != NULL) ? strtok(NULL, " \t\r\n") : NULL;
        double v;
        if (tok1 != NULL && tok2 != NULL && tok3 == NULL &&
            valid_time(tok1) && valid_num(tok2, &v)) {
            if (n == 0) { mn = v; mx = v; }
            if (v < mn) mn = v;
            if (v > mx) mx = v;
            sum += v;
            n++;
        } else {
            malformed++;
        }
    }
    fclose(fh);
    printf("samples=%ld\n", n);
    if (n > 0) {
        printf("min=%.3f\n", mn);
        printf("max=%.3f\n", mx);
        printf("mean=%.3f\n", sum / (double)n);
        printf("range=%.3f\n", mx - mn);
    } else {
        printf("min=NA\n");
        printf("max=NA\n");
        printf("mean=NA\n");
        printf("range=NA\n");
    }
    printf("malformed=%ld\n", malformed);
    return 0;
}
EOF

cc -std=c11 -O2 -o /app/dist/kilnstat /app/src/kilnstat.c -lm

# PATH install: copy (not symlink, so /app/dist churn cannot break it) at the
# canonical prefix so bare-name invocation works from any directory.
install -m 0755 /app/dist/kilnstat /usr/local/bin/kilnstat

command -v kilnstat
sh -c 'cd /tmp && command -v kilnstat'
sh -c 'cd /tmp && kilnstat /app/data/shift-07.log'

echo "solve.sh done"
ls -l /app/src/kilnstat.c /app/dist/kilnstat /usr/local/bin/kilnstat
