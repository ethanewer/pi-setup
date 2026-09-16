/* Image pipeline deliverable for the jerkin-cleat task.
 *
 * Usage: image_pipeline INPUT_DIR OUTPUT_DIR REPORT_FILE
 *
 * For every regular file in INPUT_DIR (lexicographic order):
 *   - decode with stb_image as 4-channel RGBA;
 *   - vertically mirror it (row r becomes row H-1-r, all channels);
 *   - write it as a 4-channel RGBA PNG  <stem>.png  into OUTPUT_DIR;
 *   - print  OK <name>  to stdout.
 * If the library reports that the input cannot be decoded:
 *   - print  FAIL <name> <reason>  to stdout;
 *   - append  FAIL <name> <reason>  to REPORT_FILE;
 *   - produce no output image for that input.
 * Exit 0 once every input has been processed.
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
    if (argc != 4) {
        fprintf(stderr, "usage: image_pipeline INPUT_DIR OUTPUT_DIR REPORT_FILE\n");
        return 2;
    }
    const char *in = argv[1];
    const char *out = argv[2];
    const char *report_path = argv[3];

    struct stat st2;
    if (mkdir(out, 0755) != 0 && !(stat(out, &st2) == 0 && S_ISDIR(st2.st_mode))) {
        fprintf(stderr, "cannot use output dir %s\n", out);
        return 1;
    }
    FILE *report = fopen(report_path, "w");
    if (!report) {
        fprintf(stderr, "cannot open report file %s\n", report_path);
        return 1;
    }

    DIR *d = opendir(in);
    if (!d) {
        fprintf(stderr, "cannot open input dir %s\n", in);
        fclose(report);
        return 1;
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
            const char *reason = stbi_failure_reason();
            if (!reason)
                reason = "decode failed";
            printf("FAIL %s %s\n", names[i], reason);
            fprintf(report, "FAIL %s %s\n", names[i], reason);
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
            printf("FAIL %s %s\n", names[i], stbi_failure_reason() ? stbi_failure_reason() : "write failed");
            fprintf(report, "FAIL %s write failed\n", names[i]);
            stbi_image_free(img);
            continue;
        }
        stbi_image_free(img);
        printf("OK %s\n", names[i]);
    }
    fclose(report);
    return 0;
}