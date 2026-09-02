#!/bin/bash
# Oracle for cobalt-marlin: repair the abort path in /app/src/batchstat.c so
# it returns normally through the registered atexit lifecycle instead of
# short-circuiting process termination, then rebuild. Never reads /tests.
set -eu

SRC="/app/src/batchstat.c"

# The fixed source: identical to the shipped tool except the too-many-errors
# abort path now closes the input and returns 2 through run()/main(), so the
# atexit-registered cleanup_registry() runs, writes the audit line, and frees
# the whole registry before the process ends.
cat > "$SRC" <<'C'
/*
 * batchstat - per-tag running totals for metric batches.
 *
 * Invocation:  batchstat <input.txt> <report.txt>
 *
 * Each input line is `TAG VALUE` (exactly one space between them), where
 * TAG is [a-z][a-z0-9_]* and VALUE is an optionally negative decimal
 * integer.  Any other line (empty line, uppercase tag, no space, bad or
 * missing value, trailing junk) is malformed.  Malformed lines are counted
 * and processing CONTINUES.
 *
 * A correct run:
 *   - accumulates the sum of VALUE per distinct TAG (case-sensitive);
 *   - if the malformed-line count exceeds MAX_ERRORS, prints exactly one
 *     line `aborted:too-many-errors` and terminates with exit code 2 (the
 *     per-tag sums are NOT printed on an aborted run);
 *   - otherwise prints one line `sum:<TAG>=<total>` per distinct tag in
 *     ascending byte-wise (strcmp) tag order, then `errors:<count>`, and
 *     returns 0 from main;
 *   - the report file contains exactly one line, `audit:tags=<n>`, where
 *     <n> is the number of distinct registry tags torn down.  It is written
 *     by cleanup_registry(), which is registered with atexit() and MUST run
 *     on BOTH the success and the aborted path, on the way out.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "tags.h"

#define MAX_ERRORS 8

typedef struct {
    char *tag;
    long total;
} Entry;

static Entry *g_entries = NULL;
static size_t g_n = 0;
static size_t g_cap = 0;
static FILE *g_report = NULL;

static int find_entry(const char *tag) {
    for (size_t i = 0; i < g_n; i++) {
        if (strcmp(g_entries[i].tag, tag) == 0) {
            return (int)i;
        }
    }
    return -1;
}

/* Registered with atexit(): writes the audit line, closes the report, and
 * frees every registry allocation. */
static void cleanup_registry(void) {
    if (g_report) {
        fprintf(g_report, "audit:tags=%zu\n", g_n);
        fclose(g_report);
        g_report = NULL;
    }
    for (size_t i = 0; i < g_n; i++) {
        free(g_entries[i].tag);
    }
    free(g_entries);
    g_entries = NULL;
    g_n = 0;
    g_cap = 0;
}

static void sort_entries(void) {
    for (size_t i = 1; i < g_n; i++) {
        Entry t = g_entries[i];
        size_t j = i;
        while (j > 0 && strcmp(g_entries[j - 1].tag, t.tag) > 0) {
            g_entries[j] = g_entries[j - 1];
            j--;
        }
        g_entries[j] = t;
    }
}

int run(const char *input_path, const char *report_path) {
    FILE *in = fopen(input_path, "r");
    if (!in) {
        fprintf(stderr, "batchstat: cannot open %s\n", input_path);
        return 2;
    }
    g_report = fopen(report_path, "w");
    if (!g_report) {
        fprintf(stderr, "batchstat: cannot open report %s\n", report_path);
        fclose(in);
        return 2;
    }
    atexit(cleanup_registry);

    char line[4096];
    long errors = 0;
    while (fgets(line, sizeof line, in)) {
        size_t len = strlen(line);
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
            line[--len] = '\0';
        }
        char *sp = strchr(line, ' ');
        long value = 0;
        if (sp) {
            *sp = '\0';
            const char *rest = sp + 1;
            if (tag_valid(line) && parse_long(rest, &value)) {
                int idx = find_entry(line);
                if (idx >= 0) {
                    g_entries[idx].total += value;
                } else {
                    if (g_n == g_cap) {
                        size_t nc = g_cap ? g_cap * 2 : 8;
                        Entry *t = realloc(g_entries, nc * sizeof(Entry));
                        if (!t) {
                            fclose(in);
                            return 3;
                        }
                        g_entries = t;
                        g_cap = nc;
                    }
                    char *copy = malloc(strlen(line) + 1);
                    if (!copy) {
                        fclose(in);
                        return 3;
                    }
                    strcpy(copy, line);
                    g_entries[g_n].tag = copy;
                    g_entries[g_n].total = value;
                    g_n++;
                }
                continue;
            }
        }
        errors++;
        if (errors > MAX_ERRORS) {
            printf("aborted:too-many-errors\n");
            fflush(stdout);
            /* FIXED: close the input and return normally.  The registered
             * exit lifecycle (atexit -> cleanup_registry) then runs on the
             * way out, so the audit line is written and every registry
             * allocation is freed before the process ends. */
            fclose(in);
            return 2;
        }
    }
    fclose(in);

    sort_entries();
    for (size_t i = 0; i < g_n; i++) {
        printf("sum:%s=%ld\n", g_entries[i].tag, g_entries[i].total);
    }
    printf("errors:%ld\n", errors);
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <input.txt> <report.txt>\n", argv[0]);
        return 2;
    }
    return run(argv[1], argv[2]);
}
C

# Rebuild the deliverable binary from the repaired source.
make -C /app/src clean >/dev/null 2>&1 || true
make -C /app/src >/dev/null

# Sanity: visible sample (success path) + a synthetic abort path check.
REP=$(mktemp)
OUT=$(make -s -C /app/src >/dev/null 2>&1; /app/src/batchstat /app/sample_input.txt "$REP")
test "$OUT" = "$(printf 'sum:alpha=15\nsum:beta=-5\nsum:total=12\nerrors:3')"
test "$(cat "$REP")" = "audit:tags=3"
BAD=$(mktemp)
{ printf 'alpha 1\n'; for i in 1 2 3 4 5 6 7 8 9; do printf 'junk line %d\n' "$i"; done; } > "$BAD"
OUT2=$(/app/src/batchstat "$BAD" "$REP"; echo "rc=$?")
test "$OUT2" = "$(printf 'aborted:too-many-errors\nrc=2')"
test "$(cat "$REP")" = "audit:tags=1"
rm -f "$REP" "$BAD"

echo "solve.sh done -> repaired $SRC and rebuilt /app/src/batchstat"
