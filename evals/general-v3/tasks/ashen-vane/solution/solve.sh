#!/bin/bash
# ashen-vane oracle: author edgecheck.c from the spec, compile the native
# binary to /app/bin/edgecheck, and smoke-run it on a locally generated
# fixture. Never reads /tests.
set -euo pipefail

mkdir -p /app/src /app/bin /tmp/ashen-vane-smoke

# ---- 1. author the source (this IS the deliverable work) ---------------- #
cat > /app/src/edgecheck.c <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAXK 16

static void die(const char *msg) {
    fprintf(stderr, "error: %s\n", msg);
    exit(1);
}

/* read entire file into a NUL-terminated buffer; die on failure */
static char *slurp(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) die("cannot open input file");
    if (fseek(f, 0, SEEK_END) != 0) die("seek failed");
    long sz = ftell(f);
    if (sz < 0) die("tell failed");
    rewind(f);
    char *buf = malloc((size_t)sz + 1);
    if (!buf) die("out of memory");
    if (sz > 0 && fread(buf, 1, (size_t)sz, f) != (size_t)sz) die("read failed");
    buf[sz] = '\0';
    fclose(f);
    return buf;
}

/* parse one whitespace-delimited token as a full double; returns 0 if the
   token is not exactly a number */
static int token_to_double(const char *tok, double *out) {
    if (!tok || !*tok) return 0;
    char *end;
    double v = strtod(tok, &end);
    if (end == tok) return 0;
    while (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n') end++;
    if (*end != '\0') return 0;
    *out = v;
    return 1;
}

static int token_to_long(const char *tok, long *out) {
    if (!tok || !*tok) return 0;
    char *end;
    long v = strtol(tok, &end, 10);
    if (end == tok) return 0;
    while (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n') end++;
    if (*end != '\0') return 0;
    *out = v;
    return 1;
}

/* next whitespace-delimited token from a cursor; dies if none */
static char *next_tok(char **cur) {
    char *p = *cur;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    if (*p == '\0') die("unexpected end of file");
    char *start = p;
    while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n') p++;
    if (*p) { *p = '\0'; p++; }
    *cur = p;
    return start;
}

/* strip '#' comments (to end of line) in place */
static void strip_comments(char *s) {
    char *r = s, *w = s;
    while (*r) {
        if (*r == '#') {
            while (*r && *r != '\n') r++;
        } else {
            *w++ = *r++;
        }
    }
    *w = '\0';
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: edgecheck <weights-path> <image-path>\n");
        return 2;
    }

    /* ---- weights file (argument 1, positionally) ---- */
    char *wbuf = slurp(argv[1]);
    char *nl = strchr(wbuf, '\n');
    if (!nl) die("kernel header line missing");
    *nl = '\0';
    /* header: "kernel <K>" and nothing else on the line */
    char *hp = wbuf;
    while (*hp == ' ' || *hp == '\t') hp++;
    if (strncmp(hp, "kernel", 6) != 0) die("kernel header must start with 'kernel'");
    hp += 6;
    if (*hp != ' ' && *hp != '\t') die("kernel header malformed");
    while (*hp == ' ' || *hp == '\t') hp++;
    long K;
    if (!token_to_long(hp, &K)) die("kernel K must be an integer");
    if (K < 1 || K > MAXK) die("kernel K out of range 1..16");

    double *w = malloc(sizeof(double) * (size_t)(K * K));
    char *wcur = nl + 1;
    for (long i = 0; i < K * K; i++) {
        char *tok = next_tok(&wcur);
        if (!token_to_double(tok, &w[i])) die("kernel value not numeric");
    }
    /* only whitespace may remain */
    while (*wcur) {
        if (*wcur != ' ' && *wcur != '\t' && *wcur != '\r' && *wcur != '\n')
            die("surplus tokens after kernel values");
        wcur++;
    }

    /* ---- image file (argument 2, positionally) ---- */
    char *ibuf = slurp(argv[2]);
    strip_comments(ibuf);
    char *icur = ibuf;
    char *magic = next_tok(&icur);
    if (strcmp(magic, "P2") != 0) die("image magic must be P2");
    long width, height, maxval;
    if (!token_to_long(next_tok(&icur), &width) || width <= 0) die("bad width");
    if (!token_to_long(next_tok(&icur), &height) || height <= 0) die("bad height");
    if (!token_to_long(next_tok(&icur), &maxval) || maxval <= 0) die("bad maxval");
    size_t npix = (size_t)width * (size_t)height;
    long *img = malloc(sizeof(long) * npix);
    for (size_t i = 0; i < npix; i++) {
        char *tok = next_tok(&icur);
        if (!token_to_long(tok, &img[i])) die("pixel must be an integer");
        if (img[i] < 0 || img[i] > maxval) die("pixel out of range");
    }
    while (*icur) {
        if (*icur != ' ' && *icur != '\t' && *icur != '\r' && *icur != '\n')
            die("surplus tokens after pixels");
        icur++;
    }

    /* ---- scoring ---- */
    long c = K / 2;
    double total = 0.0;
    for (long i = 0; i < height; i++) {
        for (long j = 0; j < width; j++) {
            double acc = 0.0;
            for (long u = 0; u < K; u++) {
                for (long v = 0; v < K; v++) {
                    long ii = i + u - c;
                    long jj = j + v - c;
                    if (ii < 0) ii = 0;
                    if (ii > height - 1) ii = height - 1;
                    if (jj < 0) jj = 0;
                    if (jj > width - 1) jj = width - 1;
                    acc += w[u * K + v] * (double)img[ii * width + jj];
                }
            }
            total += fabs(acc);
        }
    }
    printf("score=%.2f\n", total);
    return 0;
}
C

# ---- 2. compile the deliverable binary ---------------------------------- #
gcc -O2 -Wall -o /app/bin/edgecheck /app/src/edgecheck.c -lm
chmod 0755 /app/bin/edgecheck

# ---- 3. smoke run on a locally generated fixture ------------------------ #
printf 'kernel 3\n0.0 1.0 0.0\n1.0 2.0 1.0\n0.0 1.0 0.0\n' > /tmp/ashen-vane-smoke/w.txt
printf 'P2 3 3 255\n1 2 3 4 5 6 7 8 9\n' > /tmp/ashen-vane-smoke/img.pgm
out=$(/app/bin/edgecheck /tmp/ashen-vane-smoke/w.txt /tmp/ashen-vane-smoke/img.pgm)
echo "smoke: $out"
case "$out" in
  score=*) : ;;
  *) echo "smoke run failed: $out" >&2; exit 1 ;;
esac

# swapped arguments must be rejected (nonzero exit, empty stdout)
if /app/bin/edgecheck /tmp/ashen-vane-smoke/img.pgm /tmp/ashen-vane-smoke/w.txt >/tmp/ashen-vane-smoke/sw.out 2>/dev/null; then
  echo "swapped invocation unexpectedly succeeded" >&2; exit 1
fi
[ ! -s /tmp/ashen-vane-smoke/sw.out ] || { echo "swapped invocation wrote stdout" >&2; exit 1; }

echo "solve.sh done -> /app/bin/edgecheck and /app/src/edgecheck.c"
ls -l /app/bin/edgecheck /app/src/edgecheck.c
