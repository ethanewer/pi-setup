/* Reference pipeline for the jerkin-cleat verifier.
 *
 * Decodes every decodable file in a directory with stb_image (4-channel RGBA),
 * vertically mirrors the raster (row r becomes row H-1-r), and writes a
 * 4-channel RGBA PNG via stb_image_write.  Files the library cannot decode are
 * skipped: they produce no output at all.  The verifier uses this program's
 * outputs as ground truth because it is built from the same pinned upstream
 * headers the task ships.
 *
 * Usage: ref_pipeline INPUT_DIR OUTPUT_DIR
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

#define STB_IMAGE_IMPLEMENTATION
#include "/app/src/stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "/app/src/stb_image_write.h"

static int namecmp(const void *a, const void *b) {
    return strcmp(*(const char **)a, *(const char **)b);
}

/* vertical mirror: row r <-> row H-1-r, every channel including alpha */
static void vertflip(unsigned char *data, int w, int h) {
    int row = w * 4;
    for (int r = 0; r < h / 2; r++) {
        unsigned char *top = data + (size_t)r * row;
        unsigned char *bot = data + (size_t)(h - 1 - r) * row;
        for (int i = 0; i < row; i++) {
            unsigned char t = top[i];
            top[i] = bot[i];
            bot[i] = t;
        }
    }
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: ref_pipeline INPUT_DIR OUTPUT_DIR\n");
        return 2;
    }
    const char *in = argv[1];
    const char *out = argv[2];
    mkdir(out, 0755);

    DIR *d = opendir(in);
    if (!d) {
        fprintf(stderr, "cannot open input dir %s\n", in);
        return 2;
    }
    char **names = NULL;
    int n = 0, cap = 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.')
            continue;
        char path[4096];
        snprintf(path, sizeof path, "%s/%s", in, e->d_name);
        struct stat st;
        if (stat(path, &st) != 0 || !S_ISREG(st.st_mode))
            continue;
        if (n == cap) {
            cap = cap ? cap * 2 : 16;
            names = realloc(names, (size_t)cap * sizeof(char *));
        }
        names[n++] = strdup(e->d_name);
    }
    closedir(d);
    qsort(names, n, sizeof(char *), namecmp);

    for (int i = 0; i < n; i++) {
        char path[4096];
        snprintf(path, sizeof path, "%s/%s", in, names[i]);
        const char *dot = strrchr(names[i], '.');
        int w, h, c;
        unsigned char *img = stbi_load(path, &w, &h, &c, 4);
        if (!img) {
            printf("REF SKIP %s: %s\n", names[i], stbi_failure_reason());
            continue;
        }
        vertflip(img, w, h);
        char outp[4096];
        if (dot)
            snprintf(outp, sizeof outp, "%s/%.*s.png", out,
                     (int)(dot - names[i]), names[i]);
        else
            snprintf(outp, sizeof outp, "%s/%s.png", out, names[i]);
        if (!stbi_write_png(outp, w, h, 4, img, 0)) {
            fprintf(stderr, "reference write failed: %s\n", outp);
            return 2;
        }
        stbi_image_free(img);
        printf("REF OK %s\n", names[i]);
    }
    return 0;
}