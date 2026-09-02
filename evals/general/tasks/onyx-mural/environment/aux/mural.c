/* onyx-mural reverse-engineering target (aux build - NOT shipped as source).
 * Reads a grayscale grid and emits a 1-bit dithered "mural" as ASCII art.
 * Grid file: whitespace-separated tokens; first two tokens are H W, then
 * H*W pixel values (each 0..255).
 * Serpentine Floyd-Steinberg error diffusion to two levels (0 / 255),
 * threshold 128, weights 7/16 3/16 5/16 1/16, C-truncating division.
 * Output: H rows, W chars per row ('#' = white, '.' = black), newline each. */
#include <stdio.h>
#include <stdlib.h>

#define MAXSIDE 512

static unsigned char in_[MAXSIDE][MAXSIDE];
static int err[MAXSIDE][MAXSIDE];

static void push(int y, int x, int num) {
    if (y < 0 || y >= MAXSIDE || x < 0 || x >= MAXSIDE) return;
    err[y][x] += num;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: mural <grid>\n"); return 2; }
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror("open"); return 2; }

    int H = 0, W = 0;
    if (fscanf(f, "%d %d", &H, &W) != 2) { fclose(f); return 2; }
    if (H < 0 || W < 0 || H > MAXSIDE || W > MAXSIDE) { fclose(f); return 2; }

    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            int v = 0;
            if (fscanf(f, "%d", &v) != 1) v = 0;
            in_[y][x] = (unsigned char)(v & 0xffu);
        }
    fclose(f);

    for (int y = 0; y < H; y++) {
        int l2r = (y % 2 == 0);
        for (int k = 0; k < W; k++) {
            int x = l2r ? k : (W - 1 - k);
            int old = (int)in_[y][x] + err[y][x];
            int new = (old >= 128) ? 255 : 0;
            int e = old - new;
            putchar(new == 255 ? '#' : '.');
            if (l2r) {
                if (x + 1 < W)          push(y,     x + 1, e * 7 / 16);
                if (x - 1 >= 0 && y + 1 < H) push(y + 1, x - 1, e * 3 / 16);
                if (y + 1 < H)          push(y + 1, x,     e * 5 / 16);
                if (x + 1 < W && y + 1 < H)  push(y + 1, x + 1, e * 1 / 16);
            } else {
                if (x - 1 >= 0)         push(y,     x - 1, e * 7 / 16);
                if (x + 1 < W && y + 1 < H)  push(y + 1, x + 1, e * 3 / 16);
                if (y + 1 < H)          push(y + 1, x,     e * 5 / 16);
                if (x - 1 >= 0 && y + 1 < H) push(y + 1, x - 1, e * 1 / 16);
            }
        }
        putchar('\n');
    }
    return 0;
}
