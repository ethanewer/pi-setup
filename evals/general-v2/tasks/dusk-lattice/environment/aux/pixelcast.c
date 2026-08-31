/*
 * pixelcast - proprietary scene-postprocessing codec.
 * Shipped as a stripped binary only; source is build-context only and is
 * deleted from the image after compilation.
 *
 * Usage: pixelcast <in.ppm>   (ASCII P2 PPM; transformed P2 PPM on stdout)
 */
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>

/* Read the next unsigned decimal token, skipping ASCII whitespace and
 * '#' comments that run to end of line. Returns 1 ok, 0 EOF, -1 parse error. */
static int tok(FILE *f, long *out) {
    int c;
    for (;;) {
        c = fgetc(f);
        if (c == EOF) return 0;
        if (c == '#') {
            do { c = fgetc(f); } while (c != EOF && c != '\n');
            continue;
        }
        if (isspace(c)) continue;
        break;
    }
    if (!isdigit(c)) return -1;
    long v = 0;
    while (c != EOF && isdigit(c)) {
        v = v * 10 + (c - '0');
        c = fgetc(f);
    }
    if (c != EOF) ungetc(c, f);
    *out = v;
    return 1;
}

static unsigned char rev8(unsigned char v) {
    unsigned char r = 0;
    for (int i = 0; i < 8; i++)
        if (v & (1u << i)) r |= (unsigned char)(1u << (7 - i));
    return r;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: pixelcast <in.ppm>\n");
        return 2;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("pixelcast: open"); return 2; }

    /* magic: expect P2 (comments/whitespace tolerated anywhere) */
    int c;
    for (;;) {
        c = fgetc(f);
        if (c == EOF) { fprintf(stderr, "pixelcast: bad magic\n"); return 1; }
        if (c == '#') {
            do { c = fgetc(f); } while (c != EOF && c != '\n');
            continue;
        }
        if (isspace(c)) continue;
        break;
    }
    if (c != 'P' || fgetc(f) != '2') {
        fprintf(stderr, "pixelcast: bad magic\n");
        return 1;
    }

    long w, h, maxv;
    if (tok(f, &w) != 1 || tok(f, &h) != 1 || tok(f, &maxv) != 1) {
        fprintf(stderr, "pixelcast: bad header\n");
        return 1;
    }
    if (w <= 0 || h <= 0 || w > 4096L || h > 4096L) {
        fprintf(stderr, "pixelcast: bad dimensions\n");
        return 1;
    }
    if (maxv != 255) {
        fprintf(stderr, "pixelcast: unsupported maxval (need 255)\n");
        return 1;
    }

    long n = w * h;
    unsigned char *px = malloc((size_t)n * 3);
    if (!px) { fprintf(stderr, "pixelcast: oom\n"); return 2; }
    for (long i = 0; i < n * 3; i++) {
        long v;
        if (tok(f, &v) != 1 || v < 0 || v > 255) {
            fprintf(stderr, "pixelcast: bad pixel data\n");
            return 1;
        }
        px[i] = (unsigned char)v;
    }
    fclose(f);

    /* Scene postprocess: rotate the frame 90 degrees clockwise, then push
     * every channel through the fixed tone table and swap the channel
     * order. Emitted as canonical ASCII P2 (single-space separated,
     * one row per line). */
    printf("P2\n%ld %ld\n255\n", h, w);
    for (long rr = 0; rr < w; rr++) {          /* result rows    = old width  */
        for (long cc = 0; cc < h; cc++) {      /* result columns = old height */
            long orow = h - 1 - cc;
            long ocol = rr;
            const unsigned char *p = &px[(orow * w + ocol) * 3];
            int v0 = rev8(p[2]);               /* blue  -> first channel  */
            int v1 = rev8(p[1]);               /* green -> middle         */
            int v2 = rev8(p[0]);               /* red   -> last           */
            int vals[3] = {v0, v1, v2};
            for (int k = 0; k < 3; k++) {
                if (cc > 0 || k > 0) putchar(' ');
                printf("%d", vals[k]);
            }
            if (cc == h - 1) putchar('\n');
        }
    }
    free(px);
    return 0;
}
