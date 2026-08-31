#!/bin/bash
# Oracle for briar-anvil: repair the memledger lifecycle in /app/src/ledger.c
# (finish unwinds normally, full cleanup runs), rebuild, and sanity-check.
# Never reads /tests.
set -eu

TARGET="/app/src/ledger.c"

cat > "$TARGET" <<'EOF'
/*
 * ledger.c — memledger main logic.
 *
 * memledger replays a tiny allocation ledger:
 *
 *   alloc <label> <size>   register an active record (duplicate label = error)
 *   free <label>           release an active record (unknown label = error)
 *   finish                 stop reading; ignore everything after this line
 *
 * Any other line is malformed and counted. At the end (or when `finish` is
 * seen) the tool prints one `active:<label>=<size>` line per still-active
 * record sorted by label, then a final `totals:allocs=<A>,bytes=<B>,errors=<E>`
 * line, and exits 0.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "util.h"

typedef struct Rec {
    char *label;
    long size;
    struct Rec *next;
} Rec;

/* Global registry of active records (unsorted insertion order). */
static Rec *g_table = NULL;

/* Heap-allocated global counters block. */
struct Stats {
    long allocs;
    long bytes;
    long errors;
};

static struct Stats *g_stats = NULL;

/* Runs at the very end of main(): releases the global stats block. */
static void release_globals(void)
{
    free(g_stats);
    g_stats = NULL;
}

/* Frees every record and label in the global table. */
static void free_table(void)
{
    Rec *r = g_table;
    while (r != NULL) {
        Rec *nxt = r->next;
        free(r->label);
        free(r);
        r = nxt;
    }
    g_table = NULL;
}

static char *dup_str(const char *s)
{
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (p != NULL) {
        memcpy(p, s, n);
    }
    return p;
}

static int is_word_char(char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
           (c >= '0' && c <= '9') || c == '_';
}

static int valid_label(const char *s)
{
    size_t i;
    if (s[0] == '\0') {
        return 0;
    }
    for (i = 0; s[i] != '\0'; i++) {
        if (!is_word_char(s[i])) {
            return 0;
        }
    }
    return 1;
}

static int valid_size(const char *s)
{
    size_t i;
    if (s[0] == '\0') {
        return 0;
    }
    for (i = 0; s[i] != '\0'; i++) {
        if (s[i] < '0' || s[i] > '9') {
            return 0;
        }
    }
    return 1;
}

static Rec *find_rec(const char *label)
{
    Rec *r;
    for (r = g_table; r != NULL; r = r->next) {
        if (strcmp(r->label, label) == 0) {
            return r;
        }
    }
    return NULL;
}

/* Returns 0 on success, -1 on duplicate label. */
static int cmd_alloc(const char *label, long size)
{
    Rec *r;
    char *dup;

    if (find_rec(label) != NULL) {
        return -1;
    }
    dup = dup_str(label);
    if (dup == NULL) {
        return -1;
    }
    r = malloc(sizeof *r);
    if (r == NULL) {
        free(dup);
        return -1;
    }
    r->label = dup;
    r->size = size;
    r->next = g_table;
    g_table = r;
    return 0;
}

/* Returns 0 on success, -1 when the label is not active. */
static int cmd_free(const char *label)
{
    Rec **pp = &g_table;
    while (*pp != NULL) {
        if (strcmp((*pp)->label, label) == 0) {
            Rec *dead = *pp;
            *pp = dead->next;
            free(dead->label);
            free(dead);
            return 0;
        }
        pp = &(*pp)->next;
    }
    return -1;
}

static int cmp_rec(const void *a, const void *b)
{
    const Rec *ra = *(Rec *const *)a;
    const Rec *rb = *(Rec *const *)b;
    return strcmp(ra->label, rb->label);
}

/* Prints the end-of-run report. */
static void report(void)
{
    size_t count = 0;
    size_t i;
    Rec *r;
    Rec **vec;

    for (r = g_table; r != NULL; r = r->next) {
        count++;
    }
    vec = malloc((count > 0 ? count : 1) * sizeof *vec);
    if (vec != NULL) {
        i = 0;
        for (r = g_table; r != NULL; r = r->next) {
            vec[i++] = r;
        }
        qsort(vec, count, sizeof *vec, cmp_rec);
        for (i = 0; i < count; i++) {
            printf("active:%s=%ld\n", vec[i]->label, vec[i]->size);
        }
        free(vec);
    } else {
        for (r = g_table; r != NULL; r = r->next) {
            printf("active:%s=%ld\n", r->label, r->size);
        }
    }
    printf("totals:allocs=%ld,bytes=%ld,errors=%ld\n",
           g_stats->allocs, g_stats->bytes, g_stats->errors);
}

/* Processes the whole file; frees the line buffer before returning.
 * `finish` sets the stop flag and unwinds normally so main() runs the full
 * cleanup lifecycle (free_table + free of the line buffer + release_globals)
 * before printing the report. */
static void process(FILE *fh)
{
    char *buf = NULL;
    size_t cap = 0;
    long n;

    while ((n = read_line(fh, &buf, &cap)) >= 0) {
        char *line = buf;
        char *cmd;
        char *rest;

        if (n > 0 && line[n - 1] == '\r') {
            line[n - 1] = '\0';
        }

        /* Split "cmd rest" on the first space; rest may be NULL. */
        rest = strchr(line, ' ');
        if (rest != NULL) {
            *rest = '\0';
            rest = rest + 1;
        }
        cmd = line;

        if (strcmp(cmd, "finish") == 0) {
            if (rest == NULL) {
                break; /* stop reading; report is printed by main() */
            }
            g_stats->errors++;
            continue;
        }

        if (strcmp(cmd, "alloc") == 0 && rest != NULL) {
            char *sp = strchr(rest, ' ');
            if (sp != NULL) {
                *sp = '\0';
                if (valid_label(rest) && valid_size(sp + 1)) {
                    long size = atol(sp + 1);
                    if (cmd_alloc(rest, size) == 0) {
                        g_stats->allocs++;
                        g_stats->bytes += size;
                        continue;
                    }
                }
            }
            g_stats->errors++;
            continue;
        }

        if (strcmp(cmd, "free") == 0 && rest != NULL) {
            if (strchr(rest, ' ') == NULL && valid_label(rest) &&
                cmd_free(rest) == 0) {
                continue;
            }
            g_stats->errors++;
            continue;
        }

        g_stats->errors++;
    }

    free(buf);
}

int main(int argc, char **argv)
{
    FILE *fh;

    if (argc != 2) {
        fprintf(stderr, "usage: memledger <file>\n");
        return 2;
    }

    g_stats = calloc(1, sizeof *g_stats);
    if (g_stats == NULL) {
        return 2;
    }

    fh = fopen(argv[1], "r");
    if (fh == NULL) {
        fprintf(stderr, "memledger: cannot open %s\n", argv[1]);
        release_globals();
        return 2;
    }

    process(fh);
    fclose(fh);
    report();
    free_table();
    release_globals();
    return 0;
}
EOF

rm -f /app/src/memledger
make -C /app/src

# Sanity: correct report on the visible sample.
/app/src/memledger /app/sample.ledger

echo "solve.sh done -> $TARGET and /app/src/memledger"
ls -l "$TARGET" /app/src/memledger
