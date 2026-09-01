#!/bin/bash
# Oracle for tasks/raven-jetty (executes-deliverable).
#
# Creates every deliverable by doing the work: writes each source deliverable,
# then RUNS each build/generation step so every log and binary is a real
# artifact of executing that work (never a cat'ed canned answer). None of the
# tests are consulted here.
set -euo pipefail

mkdir -p /app/clone

# ---------------------------------------------------------------------------
# Job 1 - standalone static clone of the recovered "shoal" transform.
# Reads the recovered-behavior contract and implements it in C.
# ---------------------------------------------------------------------------
cat > /app/clone/app.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    size_t cap = 65536;
    size_t n = 0;
    unsigned char *b = (unsigned char *)malloc(cap);
    unsigned char *rev;
    unsigned char *out;
    size_t r, i;
    unsigned k;
    if (!b)
        return 3;

    while ((r = fread(b + n, 1, 4096, stdin)) > 0) {
        n += r;
        if (n == cap) {
            unsigned char *nb;
            cap *= 2;
            nb = (unsigned char *)realloc(b, cap);
            if (!nb)
                return 3;
            b = nb;
        }
    }

    rev = (unsigned char *)malloc(n ? n : 1);
    out = (unsigned char *)malloc(n ? n : 1);
    if (!rev || !out)
        return 3;

    /* STEP 1 - about-face: reverse the byte order. */
    for (i = 0; i < n; i++)
        rev[i] = b[n - 1 - i];

    /* STEP 2 - weave: running XOR key, stride 0x0D, key starts 0xC1. */
    k = 0xC1;
    for (i = 0; i < n; i++) {
        unsigned v = ((unsigned)rev[i] ^ k) & 0xFF;
        out[i] = (unsigned char)v;
        k = (k + v + 0x0D) & 0xFF;
    }

    if (fwrite(out, 1, n, stdout) != n)
        return 4;

    free(b);
    free(rev);
    free(out);
    return 0;
}
CEOF

cat > /app/clone/Makefile <<'MEOF'
CC      = gcc
CFLAGS  = -std=c11 -Wall -Wextra -O2 -static

app: app.c
	$(CC) $(CFLAGS) -o app app.c

clean:
	rm -f app
MEOF

# Build the static binary for real (in a scratch copy, then install it) so the
# deliverable /app/clone/app truly comes from compiling the deliverable source.
mkdir -p /tmp/jetclone
cp /app/clone/app.c /app/clone/Makefile /tmp/jetclone/
make -C /tmp/jetclone
cp /tmp/jetclone/app /app/clone/app

# ---------------------------------------------------------------------------
# Job 2 - engine header on the preprocessor include path.
# ---------------------------------------------------------------------------
cat > /app/include-path.sh <<'PEO'
#!/usr/bin/env bash
# Wire the engine's public header dir into the clang preprocessor include
# path (CPATH) so <hull/engine.h> resolves, then prove it by compiling and
# running a probe and recording its stdout in include-proof.log.
set -eu

cat > inj_probe.c <<'EOFPROBE'
#include <hull/engine.h>
#include <stdio.h>
int main(void)
{
    printf("probe hull_level=%d tag=%s throttle=%d\n",
           HULL_LEVEL, HULL_TAG, (int)HULL_TAKEOFF);
    return 0;
}
EOFPROBE

export CPATH=/app/engine/include
clang inj_probe.c -o inj_probe
./inj_probe > include-proof.log
PEO
chmod +x /app/include-path.sh

(cd /app && bash /app/include-path.sh && [ -s /app/include-proof.log ])

# ---------------------------------------------------------------------------
# Job 3 - distinct build modes + instrumentation.
# ---------------------------------------------------------------------------
cat > /app/build-modes.sh <<'BEO'
#!/usr/bin/env bash
# Compile ONE source under four distinct flag sets, run the fast and the
# instrumented-debug builds, and record each one's build-mode behavior.
# Optional args <lo> <hi> (default 1 100) forward to both binaries so fresh
# ranges can be probed. Coverage artifacts (.gcno/.gcda) are produced ONLY by
# the --coverage build.
set -eu

cat > bmsrc.c <<'BSRC'
#include <stdio.h>
#include <assert.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    long lo = argc > 1 ? atol(argv[1]) : 1;
    long hi = argc > 2 ? atol(argv[2]) : 100;
    long acc = 0;
    for (long i = lo; i <= hi; ++i)
        acc += i;
#ifdef NDEBUG
    const char *md = "SAILOR";
    long value = acc;
#else
    const char *md = "CAPSIZE";
    long value = acc + 7;
    assert(acc >= 0);
#endif
    printf("mode=%s lo=%ld hi=%ld acc=%ld value=%ld\n", md, lo, hi, acc, value);
    return 0;
}
BSRC

# four distinct builds from the single source (the coverage build uses a
# two-step --coverage compile+link so its artifacts are bmsrc.gcno/.gcda)
gcc -O2 -DNDEBUG -o bm_fast     bmsrc.c
gcc -g -O0 --coverage -c bmsrc.c && gcc --coverage -o bm_debug bmsrc.o
rm -f bmsrc.o
gcc -O2              -o bm_release bmsrc.c
gcc -g -O0           -o bm_trace   bmsrc.c

./bm_fast "$@" > mode-fast.log
./bm_debug "$@" > mode-debug.log
BEO
chmod +x /app/build-modes.sh

(cd /app && bash /app/build-modes.sh \
    && [ -s /app/mode-fast.log ] && [ -s /app/mode-debug.log ])

# ---------------------------------------------------------------------------
# Job 4 - repair the toy compiler so it rejects VLAs, then confirm.
# ---------------------------------------------------------------------------
cat > /app/toycc.c <<'TEOF'
/*
 * toycc.c - repaired "gull" toy compiler-rejector (raven-jetty bench).
 *
 * Reduced C subset accepted: function definitions, int declarations, scalar
 * arithmetic, control flow, and arrays whose size is a plain decimal
 * literal. Variable-length arrays (any non-literal/empty dimension) are a
 * feature this compiler genuinely lacks and MUST be rejected with a stderr
 * diagnostic and a non-zero exit - never silently accepted.
 *
 * Usage: toycc < src.c   |   toycc src.c
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Supported iff, after trimming surrounding spaces/tabs, the token inside the
 * brackets is non-empty and entirely decimal digits (e.g. "64", " 8 "). */
static int all_digits(const char *s, size_t n)
{
    size_t i;
    if (n == 0)
        return 0;
    for (i = 0; i < n; i++) {
        if (!isdigit((unsigned char)s[i]))
            return 0;
    }
    return 1;
}

/* Inspect every bracketed array dimension in one line. Any dimension that is
 * not a plain decimal literal (variable, identifier/macro, arithmetic
 * expression, or empty []) is a variable-length array -> reject. */
static int vla_in_line(const char *line)
{
    const char *p = line;
    while ((p = strchr(p, '[')) != NULL) {
        const char *q = p + 1;
        const char *end = strchr(q, ']');
        size_t n;
        if (!end)
            return 1;               /* unclosed dimension: unsupported */
        while (q < end && (*q == ' ' || *q == '\t')) q++;   /* trim front */
        while (end > q && (end[-1] == ' ' || end[-1] == '\t')) end--;
        n = (size_t)(end - q);
        if (!all_digits(q, n))
            return 1;              /* empty or non-literal -> VLA */
        p = end + 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    FILE *fp;
    char *buf = NULL;
    size_t cap = 0, len = 0;
    size_t i, lineno;
    long token_count = 0;
    char *line;
    char *nl;

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

    /* Reject the first genuinely unsupported VLA. */
    line = buf;
    lineno = 1;
    while (line) {
        nl = strchr(line, '\n');
        {
            char saved = nl ? *nl : '\0';
            if (nl)
                *nl = '\0';
            if (strchr(line, '[') && vla_in_line(line)) {
                fprintf(stderr,
                        "toycc: error: line %zu: variable-length array "
                        "not supported\n", lineno);
                free(buf);
                return 1;
            }
            if (nl)
                *nl = saved;
        }
        line = nl ? nl + 1 : NULL;
        lineno++;
    }

    /* token count for the ok report */
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

    printf("ok tokens=%ld\n", token_count);
    free(buf);
    return 0;
}
TEOF

gcc -Wall -Wextra -O2 -o /app/toycc /app/toycc.c

cat > /app/vla.c <<'VEOF'
int main(void) { int n = 9; int buf[n]; return 0; }
VEOF

# Confirm rejection: capture stderr, require a non-zero exit.
rc=0
/app/toycc /app/vla.c 2> /app/reject.log || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "toycc unexpectedly accepted the VLA" >&2
    exit 1
fi

echo "solve.sh: all deliveries in place"