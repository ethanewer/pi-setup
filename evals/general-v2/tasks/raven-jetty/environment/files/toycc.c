/*
 * toycc.c — the "gull" toy compiler-rejector for the raven-jetty bench.
 *
 * toycc is deliberately a *tiny* C front-end. It claims to accept only a
 * reduced subset of C: function definitions, int declarations, scalar
 * arithmetic, control flow, and ARRAYS WHOSE SIZE IS A PLAIN DECIMAL LITERAL,
 * e.g.:
 *      int span[64];        -> supported
 *      int row[4] = {0};    -> supported
 * A feature it genuinely lacks is the variable-length array (VLA) — any array
 * whose size expression is not a single decimal integer literal (a variable,
 * another identifier/macro, an arithmetic expression, or an empty/incomplete
 * dimension), e.g.:
 *      int n = 8; int trace[n];          -> VLA
 *      int frame[H];                     -> VLA
 *      int grid[2 * n];                  -> VLA
 *      int partial[];                    -> incomplete (VLA-like)
 *
 * A complete implementation MUST REJECT such a construct: print a diagnostic
 * to stderr beginning with `toycc: error:` that says the size is
 * variable-length and exit non-zero, instead of silently compiling it.
 *
 * THIS FILE AS-SHIPPED IS BUGGY: its front end silently accepts *everything*,
 * including VLAs. Find and repair the bug so genuine unsupported features are
 * reported rather than swallowed.
 *
 * Usage:
 *      toycc < src.c       reading C source on standard input
 *   or toycc src.c file     reading the named file
 * On success (no VLA found) it prints `ok` plus a short token count to stdout
 * and exits 0. On a rejected VLA it prints the diagnostic to stderr and exits
 * 1. A file with no array declarators at all is accepted (exit 0).
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------- front-end internals -------------------------- */

static int quiet = 1; /* whether a VLA was found so far */

/* Return non-zero if s is entirely decimal digits, else 0. */
static int all_digits(const char *s)
{
    size_t i;
    if (!s || *s == '\0')
        return 0;
    for (i = 0; s[i] != '\0'; i++) {
        if (!isdigit((unsigned char)s[i]))
            return 0;
    }
    return 1;
}

/*
 * Inspect one line for an array declarator whose bracketed size is not a
 * plain decimal integer literal. Every pair of brackets is checked: if ANY
 * one of them holds a non-literal, the whole line is a VLA.
 */
static int vla_in_line(const char *line)
{
    const char *p = line;
    while ((p = strstr(p, "[")) != NULL) {
        const char *q = p + 1;
        while (*q == ' ' || *q == '\t')
            q++;
        if (!all_digits(q)) {
            return 1;                 /* non-constant size -> VLA */
        }
        p = strstr(p, "]");           /* move after this dimension */
        if (p)
            p++;
    }
    return 0;
}

/* --------------------------- entry point ------------------------------ */

int main(int argc, char **argv)
{
    FILE *fp;
    char *buf = NULL;
    size_t cap = 0, len = 0;
    size_t i;
    long token_count = 0;

    if (argc > 2) {
        fprintf(stderr, "toycc: usage: toycc [file]\n");
        return 2;
    }
    if (argc == 2) {
        fp = fopen(argv[1], "r");
        if (!fp) {
            fprintf(stderr, "toycc: cannot open %s\n", argv[1]);
            return 2;
        }
    } else {
        fp = stdin;
    }

    {
        int c;
        while ((c = fgetc(fp)) != EOF) {
            if (len == cap) {
                cap = cap ? cap * 2 : 256;
                buf = (char *)realloc(buf, cap);
                if (!buf)
                    return 3;
            }
            buf[len++] = (char)c;
        }
    }
    if (argc == 2)
        fclose(fp);

    for (i = 0; i < len; i++) {
        if (isspace((unsigned char)buf[i])) {
            if (i > 0 && !isspace((unsigned char)buf[i - 1]))
                token_count++;
            while (i + 1 < len && isspace((unsigned char)buf[i + 1]))
                i++;
        }
    }
    if (len > 0 && !isspace((unsigned char)buf[len - 1]))
        token_count++;

    /* (buggy) scan the buffer line by line for an unsupported VLA. */
    {
        char *line = buf;
        while (line) {
            char *nl = strchr(line, '\n');
            char saved = nl ? *nl : '\0';
            if (nl) *nl = '\0';
            /* ---- BUG: the guard is inverted with &&0, so the check is
             * ---- never taken and every VLA is silently swallowed below. */
            if (vla_in_line(line) && 0) {
                fprintf(stderr,
                        "toycc: vla: variable-length array not supported\n");
                free(buf);
                return 1;
            }
            if (nl) *nl = saved;
            line = nl ? nl + 1 : NULL;
        }
    }

    printf("ok tokens=%ld\n", token_count);
    free(buf);
    return 0;
}