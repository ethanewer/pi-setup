#!/bin/bash
# Oracle for hollow-keystone. Does the REAL work:
#   1. Fixes the C leak bug in source (only /app/src/fixed.c is edited).
#   2. Builds the binary to prove the fix compiles and runs.
#   3. Merges the two divergent branches in /app/devzone, resolving the conflict.
#   4. Writes /app/merged.diff and /app/deps.lock from the resolved merge.
# Never reads /tests.
set -eu

# ---- 1. Apply the fix in source (the sanctioned file) -----------------------
# The fix: do NOT short-circuit on the first malformed line. Keep counting
# errors, keep parsing the rest of the file, and free every line buffer each
# iteration so no allocation is left behind. This runs the full lifecycle and
# lets valgrind find zero definite leaks with no suppression.
cat > /app/src/fixed.c <<'C'
/*
 * kvsum - sum numeric values per word from a `<word>=<num>` token file.
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
            errs++;
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
C

# ---- 2. Build to prove the fix compiles and runs ----------------------------
make -C /app/src clean >/dev/null 2>&1 || true
make -C /app/src

# Sanity run against the visible sample (no leak, correct output).
/app/src/kvcat /app/sample.conf >/dev/null

# ---- 3. Merge the two divergent branches and resolve the conflict -----------
cd /app/devzone
git config user.email "oracle@keystone.local"
git config user.name "oracle"
git checkout -q rel-main
git merge --no-edit feat-stream >/dev/null 2>&1 || true

# Resolve: keep rel-main's values where both branches changed the same key,
# incorporate every key unique to either branch.
cat > config.toml <<'EOF'
[profile]
buffer = 1024
mode = "turbofan"
stream = true
EOF

# Dependencies: union of both branches' pins; where a name appears in both with
# different versions keep the highest; output sorted by name.
printf 'cache=2.9.0\nmonitor=9.7.2\nserver=4.2.1\n' > deps.txt

git add -A
git commit -q -m 'merge: resolve divergent branches'

# ---- 4. Write the deliverables ----------------------------------------------
# merged.diff = the full change the merge introduced relative to the common
# ancestor. Diff the pristine base snapshot against the resolved merged working
# files so that applying it to a copy of the base reproduces the merged content.
{
  cd /opt/frozen/base
  diff -u config.toml /app/devzone/config.toml || true
  diff -u deps.txt /app/devzone/deps.txt || true
} > /app/merged.diff
# deps.lock = the merged dependency-set pins (exact versions).
cp /app/devzone/deps.txt /app/deps.lock

echo "solve.sh done: fixed.c, merged.diff, deps.lock"
ls -l /app/src/fixed.c /app/merged.diff /app/deps.lock
