#include "canvas.h"
#include "job.h"

#include <stdlib.h>
#include <string.h>

static int parse_ints(char *save, int *out, int n) {
    for (int i = 0; i < n; ++i) {
        char *tok = strtok_r(NULL, " \t", &save);
        if (tok == NULL) return 0;
        char *end = NULL;
        long v = strtol(tok, &end, 10);
        if (end == tok || *end != '\0') return 0;
        out[i] = (int)v;
    }
    if (n == 0 && out == NULL) { /* keep uniform handling below */ }
    return strtok_r(NULL, " \t", &save) == NULL;  /* no extra tokens allowed */
}

int pl_run_job(unsigned char *pix, FILE *fh) {
    char line[512];
    int applied = 0;
    while (fgets(line, sizeof line, fh) != NULL) {
        char *end = line + strlen(line);
        while (end > line && (end[-1] == '\n' || end[-1] == '\r')) *--end = '\0';
        char *save = line;
        char *verb = strtok_r(save, " \t", &save);
        if (verb == NULL) continue;
        if (verb[0] == '#') continue;
        int a[4];
        if (strcmp(verb, "dot") == 0 && parse_ints(save, a, 2)) {
            pl_dot(pix, a[0], a[1]); ++applied;
        } else if (strcmp(verb, "hline") == 0 && parse_ints(save, a, 3)) {
            pl_hline(pix, a[0], a[1], a[2]); ++applied;
        } else if (strcmp(verb, "vline") == 0 && parse_ints(save, a, 3)) {
            pl_vline(pix, a[0], a[1], a[2]); ++applied;
        } else if (strcmp(verb, "rect") == 0 && parse_ints(save, a, 4)) {
            pl_rect(pix, a[0], a[1], a[2], a[3]); ++applied;
        } else if (strcmp(verb, "fill") == 0 && parse_ints(save, a, 4)) {
            pl_fill(pix, a[0], a[1], a[2], a[3]); ++applied;
        } else if (strcmp(verb, "clear") == 0) {
            if (strtok_r(NULL, " \t", &save) == NULL) { pl_clear(pix); ++applied; }
        }
    }
    return applied;
}
