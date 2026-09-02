/* sable-ray reverse-engineering target (aux-build - NOT shipped as source).
 *
 * A terrain "sunlight" pass over a heightmap grid:
 *   1. read an H x W integer grid (values masked to 0..255),
 *   2. replace every height with the MEDIAN of the horizontally clamped
 *      3-cell window (g[y][x-1], g[y][x], g[y][x+1]) - a despike filter,
 *   3. march light rays west->east (toward +x); a ray's clearance drops by
 *      exactly 1 height unit per column step.  A cell is LIT iff its smoothed
 *      height is STRICTLY greater than the highest ray-clearance of every
 *      cell strictly west of it in the same row; column 0 is always lit.
 * Output: "LIT <count>" then H rows of '#' (lit) / '.' (shadow).
 */
#include <stdio.h>
#include <stdlib.h>

#define MAXSIDE 512

static int med3(int a, int b, int c) {
    if (a > b) { int t = a; a = b; b = t; }
    if (b > c) { int t = b; b = c; c = t; }
    if (a > b) { int t = a; a = b; b = t; }
    return b;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: raycaster <grid-file>\n"); return 2; }
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror("open"); return 2; }

    int H = 0, W = 0;
    if (fscanf(f, "%d %d", &H, &W) != 2 || H < 1 || W < 1 ||
        H > MAXSIDE || W > MAXSIDE) {
        fprintf(stderr, "bad header\n");
        fclose(f);
        return 2;
    }

    static int g[MAXSIDE][MAXSIDE];
    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            int v = 0;
            if (fscanf(f, "%d", &v) != 1) {
                fprintf(stderr, "bad grid data\n");
                fclose(f);
                return 2;
            }
            g[y][x] = v & 0xff;
        }
    }
    fclose(f);

    /* despike: horizontal median-of-3 with clamped window */
    static int s[MAXSIDE][MAXSIDE];
    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            int xl = (x > 0) ? x - 1 : 0;
            int xr = (x < W - 1) ? x + 1 : W - 1;
            s[y][x] = med3(g[y][xl], g[y][x], g[y][xr]);
        }
    }

    static char out[MAXSIDE][MAXSIDE + 2];
    long lit = 0;
    for (int y = 0; y < H; y++) {
        long lev = -(1L << 30);          /* ray clearance budget so far */
        for (int x = 0; x < W; x++) {
            int islit;
            if (x == 0) {
                islit = 1;
            } else {
                islit = (s[y][x] > lev); /* STRICTLY greater */
            }
            if (islit) lit++;
            out[y][x] = islit ? '#' : '.';
            long down = (long)s[y][x] - 1;
            long cand = lev - 1;
            lev = (cand > down) ? cand : down;
        }
        out[y][W] = '\0';
    }

    printf("LIT %ld\n", lit);
    for (int y = 0; y < H; y++) printf("%s\n", out[y]);
    return 0;
}
