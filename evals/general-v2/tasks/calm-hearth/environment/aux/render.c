/* calm-hearth reverse-engineering target (aux-build - NOT shipped as source).
 * A 3x3 low-pass (blur) convolution of an integer grid with kernel
 *       1 2 1
 *       2 4 2   , divisor 16, edges replicated (clamped).
 *       1 2 1
 * Grid file: first line "H W", then H lines of W integers (each 0..255).
 * Prints H rows of W space-separated integers to stdout. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#define MAXSIDE 1024

static int K[9] = {1, 2, 1, 2, 4, 2, 1, 2, 1};

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: render <grid>\n"); return 2; }
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror("open"); return 2; }

    int H = 0, W = 0;
    if (fscanf(f, "%d %d", &H, &W) != 2) { fclose(f); return 2; }
    if (H < 0 || W < 0 || H > MAXSIDE || W > MAXSIDE) { fclose(f); return 2; }

    static unsigned char in[MAXSIDE][MAXSIDE];
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            int v = 0;
            fscanf(f, "%d", &v);
            in[y][x] = (unsigned char)(v & 0xffu);
        }
    fclose(f);

    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            int acc = 0;
            for (int dy = 0; dy < 3; dy++) {
                int sy = y + dy - 1;
                if (sy < 0) sy = 0; else if (sy > H - 1) sy = H - 1;
                for (int dx = 0; dx < 3; dx++) {
                    int sx = x + dx - 1;
                    if (sx < 0) sx = 0; else if (sx > W - 1) sx = W - 1;
                    acc += (int)in[sy][sx] * K[dy * 3 + dx];
                }
            }
            if (x > 0) putchar(' ');
            printf("%d", acc / 16);
        }
        putchar('\n');
    }
    return 0;
}