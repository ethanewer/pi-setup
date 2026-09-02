#!/bin/bash
# moss-vane oracle: author the scorer source, compile the native binary, and
# smoke-test it on the visible fixtures. Never reads /tests.
set -eu

mkdir -p /app/src /app/bin

cat > /app/src/infer.c <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>

#define NFEATURES 16
#define MAXTOKEN 4096

/* ------------------------------------------------------------------ */
/* token reader: skips whitespace and '#' comments, returns 1 on token */
static int next_token(FILE *f, char *buf, size_t cap) {
    int c;
    for (;;) {
        c = fgetc(f);
        if (c == EOF) return 0;
        if (c == '#') {                     /* comment to end of line */
            while ((c = fgetc(f)) != EOF && c != '\n') {}
            continue;
        }
        if (!isspace(c)) break;
    }
    size_t n = 0;
    while (c != EOF && !isspace(c) && c != '#') {
        if (n + 1 < cap) buf[n++] = (char)c;
        c = fgetc(f);
    }
    if (c == '#') ungetc(c, f);
    buf[n] = '\0';
    return 1;
}

/* strict optionally-signed decimal integer */
static int parse_int(const char *s, long long *out) {
    const char *p = s;
    if (*p == '+' || *p == '-') p++;
    if (!isdigit((unsigned char)*p)) return 0;
    while (isdigit((unsigned char)*p)) p++;
    if (*p != '\0') return 0;
    errno = 0;
    char *end = NULL;
    long long v = strtoll(s, &end, 10);
    if (errno != 0 || (end && *end != '\0')) return 0;
    *out = v;
    return 1;
}

static int fail(const char *msg) {
    fprintf(stderr, "infer: %s\n", msg);
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: infer <weights-path> <image-path>\n");
        return 2;
    }

    /* ---- weights: argument 1, literally ---- */
    long long w[NFEATURES];
    for (int i = 0; i < NFEATURES; i++) w[i] = 0;
    FILE *fw = fopen(argv[1], "r");
    if (!fw) return fail("cannot open weights file");
    char tok[MAXTOKEN];
    int k = 0;
    while (k < NFEATURES && next_token(fw, tok, sizeof tok)) {
        long long v;
        if (!parse_int(tok, &v)) {
            fclose(fw);
            return fail("bad weights");
        }
        w[k++] = v;
    }
    /* remaining tokens must also be valid integers (validated, then ignored) */
    while (next_token(fw, tok, sizeof tok)) {
        long long v;
        if (!parse_int(tok, &v)) {
            fclose(fw);
            return fail("bad weights");
        }
    }
    fclose(fw);

    /* ---- image: argument 2, literally (ASCII PGM P2) ---- */
    FILE *fi = fopen(argv[2], "r");
    if (!fi) return fail("cannot open image file");
    long long W = 0, H = 0, M = 0;
    if (!next_token(fi, tok, sizeof tok) || strcmp(tok, "P2") != 0) {
        fclose(fi);
        return fail("bad image");
    }
    if (!next_token(fi, tok, sizeof tok) || !parse_int(tok, &W) || W < 1) {
        fclose(fi);
        return fail("bad image");
    }
    if (!next_token(fi, tok, sizeof tok) || !parse_int(tok, &H) || H < 1) {
        fclose(fi);
        return fail("bad image");
    }
    if (!next_token(fi, tok, sizeof tok) || !parse_int(tok, &M) ||
        M < 1 || M > 65535) {
        fclose(fi);
        return fail("bad image");
    }
    long long npx = W * H;
    long long *pix = malloc(sizeof(long long) * (size_t)npx);
    if (!pix) { fclose(fi); return fail("out of memory"); }
    for (long long i = 0; i < npx; i++) {
        long long v;
        if (!next_token(fi, tok, sizeof tok) || !parse_int(tok, &v) ||
            v < 0 || v > M) {
            free(pix);
            fclose(fi);
            return fail("bad image");
        }
        pix[i] = v;
    }
    if (next_token(fi, tok, sizeof tok)) {   /* trailing token */
        free(pix);
        fclose(fi);
        return fail("bad image");
    }
    fclose(fi);

    /* ---- 4x4 block sums, row-major ---- */
    long long score = 0;
    for (int br = 0; br < 4; br++) {
        long long r0 = (br * H) / 4, r1 = ((br + 1) * H) / 4;
        for (int bc = 0; bc < 4; bc++) {
            long long c0 = (bc * W) / 4, c1 = ((bc + 1) * W) / 4;
            long long s = 0;
            for (long long r = r0; r < r1; r++)
                for (long long c = c0; c < c1; c++)
                    s += pix[r * W + c];
            score += w[4 * br + bc] * s;
        }
    }
    free(pix);

    const char *cls = (score > 0) ? "POS" : (score < 0) ? "NEG" : "ZERO";
    printf("score=%lld\n", score);
    printf("class=%s\n", cls);
    return 0;
}
C

gcc -O2 -o /app/bin/infer /app/src/infer.c
chmod 0755 /app/bin/infer

# smoke test on the visible fixtures (instruction documents score=-8 / NEG)
out="$(/app/bin/infer /app/fixtures/weights.txt /app/fixtures/image.pgm)"
echo "smoke output:"
echo "$out"
echo "$out" | grep -q '^score=-8$'
echo "$out" | grep -q '^class=NEG$'

echo "oracle success"
ls -l /app/bin/infer /app/src/infer.c
