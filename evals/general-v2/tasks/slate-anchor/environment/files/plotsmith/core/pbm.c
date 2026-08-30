#include "pbm.h"

int pl_write_pbm(const char *path, const unsigned char *pix, int w, int h) {
    FILE *f = fopen(path, "w");
    if (f == NULL) return -1;
    fprintf(f, "P1\n%d %d\n", w, h);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            fprintf(f, "%d", pix[y * w + x] ? 1 : 0);
            if (x + 1 < w) fputc(' ', f);
        }
        fputc('\n', f);
    }
    fclose(f);
    return 0;
}
