#!/bin/bash
# Oracle for frost-latch: author the shelf scanner C source and Makefile,
# then build /app/bin/shelfscan. Never reads /tests.
set -eu

mkdir -p /app/bin

# ---- 1. the deliverable source ------------------------------------------------
cat > /app/shelfscan.c <<'C'
/* frost-latch shelf scanner: scores PGM image rows against a weight vector.
 * Fixed argument order: argv[1] = weights path, argv[2] = image path. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WHITESPACE " \t\r\n\v\f"

static int numtok_ok(const char *s) {
    /* [+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?  and nothing else */
    const char *p = s;
    if (*p == '+' || *p == '-') p++;
    int digits = 0;
    while (*p >= '0' && *p <= '9') { p++; digits++; }
    if (*p == '.') {
        p++;
        while (*p >= '0' && *p <= '9') { p++; digits++; }
    }
    if (digits == 0) return 0;
    if (*p == 'e' || *p == 'E') {
        p++;
        if (*p == '+' || *p == '-') p++;
        int ed = 0;
        while (*p >= '0' && *p <= '9') { p++; ed++; }
        if (ed == 0) return 0;
    }
    return *p == '\0';
}

/* Load weights: strip '#' comments, split on whitespace, validate tokens.
 * Returns 0 on success (possibly zero weights), -1 on any error. */
static int load_weights(const char *path, double **ws_out, size_t *nw_out) {
    *ws_out = NULL; *nw_out = 0;
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "shelfscan: cannot open %s\n", path); return -1; }
    char *buf = NULL; size_t cap = 0, len = 0;
    for (;;) {
        if (len + 4096 > cap) { cap = cap ? cap * 2 : 65536; buf = realloc(buf, cap);
            if (!buf) { fclose(f); return -1; } }
        size_t got = fread(buf + len, 1, 4096, f);
        len += got;
        if (got == 0) break;
    }
    fclose(f);
    if (!buf) { fprintf(stderr, "shelfscan: cannot open %s\n", path); return -1; }

    /* strip comments in place */
    size_t w = 0;
    for (size_t i = 0; i < len; i++) {
        if (buf[i] == '#') { while (i < len && buf[i] != '\n') i++; if (i >= len) break; }
        buf[w++] = buf[i];
    }
    buf[w] = '\0';
    len = w;

    double *ws = NULL; size_t nw = 0, cw = 0;
    char *save = NULL;
    for (char *tok = strtok_r(buf, WHITESPACE, &save); tok;
         tok = strtok_r(NULL, WHITESPACE, &save)) {
        if (!numtok_ok(tok)) {
            fprintf(stderr, "shelfscan: bad weight token '%s'\n", tok);
            free(buf); free(ws); return -1;
        }
        if (nw == cw) { cw = cw ? cw * 2 : 16; ws = realloc(ws, cw * sizeof(double)); }
        ws[nw++] = strtod(tok, NULL);
    }
    free(buf);
    *ws_out = ws;
    *nw_out = nw;
    return 0;
}

typedef struct {
    int width, height, maxval;
    int is_p5;
    unsigned char *data;   /* raw file bytes (for header offsets) */
    size_t dlen;
    size_t samples_off;    /* offset of first sample for P5 */
    long *samples;         /* decoded raw samples, row-major */
} pgm;

static int header_next_int(const unsigned char *d, size_t len, size_t *pos, long *out) {
    /* skip whitespace and '#'-comments */
    for (;;) {
        while (*pos < len && (d[*pos]==' '||d[*pos]=='\t'||d[*pos]=='\r'||d[*pos]=='\n'||d[*pos]=='\v'||d[*pos]=='\f')) (*pos)++;
        if (*pos < len && d[*pos] == '#') {
            while (*pos < len && d[*pos] != '\n') (*pos)++;
            continue;
        }
        break;
    }
    if (*pos >= len || d[*pos] < '0' || d[*pos] > '9') return 0;
    long v = 0;
    while (*pos < len && d[*pos] >= '0' && d[*pos] <= '9') { v = v*10 + (d[*pos]-'0'); (*pos)++; }
    *out = v;
    return 1;
}

static int load_pgm(const char *path, pgm *im) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "shelfscan: cannot open %s\n", path); return 0; }
    size_t cap = 65536, len = 0;
    unsigned char *d = malloc(cap);
    for (;;) {
        if (len + 65536 > cap) { cap *= 2; d = realloc(d, cap); }
        size_t got = fread(d + len, 1, 65536, f);
        len += got;
        if (got == 0) break;
    }
    fclose(f);
    im->data = d; im->dlen = len;

    if (len < 3 || d[0] != 'P' || (d[1] != '2' && d[1] != '5')) {
        fprintf(stderr, "shelfscan: bad PGM magic\n"); return 0;
    }
    im->is_p5 = (d[1] == '5');
    if (!(d[2]==' '||d[2]=='\t'||d[2]=='\r'||d[2]=='\n'||d[2]=='\v'||d[2]=='\f')) {
        fprintf(stderr, "shelfscan: bad PGM header\n"); return 0;
    }
    size_t pos = 2;
    long w, h, mv;
    if (!header_next_int(d, len, &pos, &w) || !header_next_int(d, len, &pos, &h) ||
        !header_next_int(d, len, &pos, &mv)) {
        fprintf(stderr, "shelfscan: bad PGM header\n"); return 0;
    }
    if (w < 1 || h < 1 || mv < 1 || mv > 65535) {
        fprintf(stderr, "shelfscan: bad PGM dimensions\n"); return 0;
    }
    im->width = (int)w; im->height = (int)h; im->maxval = (int)mv;

    size_t n = (size_t)w * (size_t)h;
    im->samples = malloc(n * sizeof(long));
    if (im->is_p5) {
        size_t bps = (mv < 256) ? 1 : 2;
        /* exactly one whitespace byte after maxval */
        if (pos >= len) { fprintf(stderr, "shelfscan: truncated PGM\n"); return 0; }
        pos += 1;
        if (len - pos < n * bps) { fprintf(stderr, "shelfscan: truncated PGM samples\n"); return 0; }
        im->samples_off = pos;
        for (size_t i = 0; i < n; i++) {
            if (bps == 1) im->samples[i] = d[pos + i];
            else im->samples[i] = ((long)d[pos + 2*i] << 8) | d[pos + 2*i + 1];
        }
    } else {
        for (size_t i = 0; i < n; i++) {
            long v;
            if (!header_next_int(d, len, &pos, &v)) {
                fprintf(stderr, "shelfscan: truncated P2 samples\n"); return 0;
            }
            im->samples[i] = v;
        }
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: shelfscan <weights-path> <image-path>\n");
        return 2;
    }
    size_t nw = 0;
    double *w = NULL;
    if (load_weights(argv[1], &w, &nw) != 0) return 2;

    pgm im;
    if (!load_pgm(argv[2], &im)) return 2;

    int n = (int)nw;
    if (n > im.width) n = im.width;

    double best = 0, worst = 0, total = 0;
    int best_r = 0, worst_r = 0, first = 1;
    for (int r = 0; r < im.height; r++) {
        double resp = 0.0;
        for (int i = 0; i < n; i++)
            resp += w[i] * (double)im.samples[(size_t)r * im.width + i];
        if (first) { best = worst = resp; best_r = worst_r = 0; first = 0; }
        else {
            if (resp > best) { best = resp; best_r = r; }
            if (resp < worst) { worst = resp; worst_r = r; }
        }
        total += resp;
    }
    double mean = total / im.height;

    printf("max %d %.4f\n", best_r, best);
    printf("min %d %.4f\n", worst_r, worst);
    printf("mean %.4f\n", mean);
    return 0;
}
C

# ---- 2. the deliverable Makefile ----------------------------------------------
cat > /app/Makefile <<'MK'
CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra
BIN = bin/shelfscan

all: $(BIN)

$(BIN): shelfscan.c | bin
	$(CC) $(CFLAGS) -o $@ shelfscan.c

bin:
	mkdir -p bin

clean:
	rm -rf bin

.PHONY: all clean
MK

# ---- 3. build the deliverable binary ------------------------------------------
make -C /app

ls -l /app/bin/shelfscan /app/shelfscan.c /app/Makefile
echo "frost-latch oracle done"
