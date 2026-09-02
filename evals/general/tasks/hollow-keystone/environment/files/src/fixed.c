/*
 * kvsum - sum numeric values per word from a `<word>=<num>` token file.
 *
 * A valid line is `WORD=NUM` where WORD is `[A-Za-z][A-Za-z0-9_]*` and NUM is a
 * run of digits (an unsigned integer). Any other line is malformed.
 *
 * The corrected kvsum must: keep accumulating valid records even when a
 * malformed line appears, print one `sum:<word>=<total>` line per distinct
 * word in ascending lexicographic order, then a final `errors:<count>` line,
 * and free every allocation before returning 0.
 *
 * THIS SHIPPED COPY IS BUGGY: on the first malformed line it bails out early
 * (skipping the rest of the file) and returns -1, leaking every record that has
 * been accumulated so far (no reference remains once the stack frame is gone).
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "tokens.h"

typedef struct {
    char *key;
    long val;
} Rec;

static int iswordchar(char c) {
    return isalnum((unsigned char)c) || c == '_';
}

/* Parse one line. On success sets *key (heap-allocated) and *val; returns 1.
 * Returns 0 for a malformed line, -1 on allocation failure. */
static int parse_line(const char *line, char **key, long *val) {
    const char *p = line;
    if (!isalpha((unsigned char)*p)) {
        return 0;
    }
    const char *s = p;
    while (iswordchar(*p)) {
        p++;
    }
    if (*p != '=') {
        return 0;
    }
    size_t k = (size_t)(p - s);
    p++;
    const char *n = p;
    if (!isdigit((unsigned char)*p)) {
        return 0;
    }
    while (isdigit((unsigned char)*p)) {
        p++;
    }
    if (*p != '\0') {
        return 0;
    }
    char *keyd = malloc(k + 1);
    if (!keyd) {
        return -1;
    }
    memcpy(keyd, s, k);
    keyd[k] = '\0';
    *key = keyd;
    *val = strtol(n, NULL, 10);
    return 1;
}

static int find(Rec *a, size_t n, const char *k) {
    for (size_t i = 0; i < n; i++) {
        if (strcmp(a[i].key, k) == 0) {
            return (int)i;
        }
    }
    return -1;
}

static void sort_recs(Rec *a, size_t n) {
    for (size_t i = 1; i < n; i++) {
        Rec t = a[i];
        size_t j = i;
        while (j > 0 && strcmp(a[j - 1].key, t.key) > 0) {
            a[j] = a[j - 1];
            j--;
        }
        a[j] = t;
    }
}

int kvsum(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "can't open %s\n", path);
        return 2;
    }
    Rec *rec = NULL;
    size_t n = 0, cap = 0;
    long errs = 0;
    char *line = NULL;
    size_t lcap = 0;

    while (read_line(f, &line, &lcap) >= 0) {
        char *key;
        long v;
        int r = parse_line(line, &key, &v);
        if (r == 1) {
            int idx = find(rec, n, key);
            if (idx >= 0) {
                rec[idx].val += v;
                free(key);
            } else {
                if (n == cap) {
                    size_t nc = cap ? cap * 2 : 8;
                    Rec *t = realloc(rec, nc * sizeof(Rec));
                    if (!t) {
                        free(key);
                        free(line);
                        fclose(f);
                        return 3;
                    }
                    rec = t;
                    cap = nc;
                }
                rec[n].key = key;
                rec[n].val = v;
                n++;
            }
        } else {
            /* BUG: short-circuit - leak everything accumulated and stop. */
            free(line);
            line = NULL;
            lcap = 0;
            fclose(f);
            return -1;
        }
        free(line);
        line = NULL;
        lcap = 0;
    }
    free(line);
    fclose(f);

    sort_recs(rec, n);
    for (size_t i = 0; i < n; i++) {
        printf("sum:%s=%ld\n", rec[i].key, rec[i].val);
    }
    printf("errors:%ld\n", errs);
    for (size_t i = 0; i < n; i++) {
        free(rec[i].key);
    }
    free(rec);
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <file>\n", argv[0]);
        return 2;
    }
    return kvsum(argv[1]);
}
