/* item-076-hard encoder ("pkb" format). Reads plaintext argv[1], writes
   compressed bytes to argv[2]. Greedy: emit a back-reference for any
   self-match of length >= 3 within a 4096-byte window, choosing the short
   form (offset<=256 && length<=5) or the long form; otherwise a literal
   token. Produces streams the sibling decompress.c decodes. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

struct BW { unsigned char *d; size_t len, cap; unsigned int cur, nb; };

static int bwput(struct BW *w, int bit) {
    if (bit) w->cur |= (1u << w->nb);
    w->nb++;
    if (w->nb == 8) {
        if (w->len >= w->cap) return 0;
        w->d[w->len++] = (unsigned char)w->cur;
        w->cur = 0;
        w->nb = 0;
    }
    return 1;
}

static int bwn(struct BW *w, uint32_t v, int n) {
    for (int k = 0; k < n; k++) {
        if (!bwput(w, (int)((v >> k) & 1u))) return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    if (fseek(f, 0, SEEK_END)) return 1;
    long s = ftell(f);
    if (fseek(f, 0, SEEK_SET)) return 1;
    if (s < 0) return 1;
    size_t sz = (size_t)s;
    unsigned char *in = (unsigned char *)malloc(sz ? sz : 1);
    if (!in) return 1;
    if (fread(in, 1, sz, f) != sz) return 1;
    fclose(f);
    FILE *o = fopen(argv[2], "wb");
    if (!o) return 1;
    size_t cap = sz * 9 / 8 + 64;
    unsigned char *data = (unsigned char *)calloc(cap ? cap : 1, 1);
    if (!data) return 1;
    struct BW w;
    w.d = data;
    w.cap = cap;
    w.len = 0;
    w.cur = 0;
    w.nb = 0;
    /* reserve 4 header bytes, written directly */
    w.len = 4;
    w.d[0] = (unsigned char)(sz & 255);
    w.d[1] = (unsigned char)((sz >> 8) & 255);
    w.d[2] = (unsigned char)((sz >> 16) & 255);
    w.d[3] = (unsigned char)((sz >> 24) & 255);
    size_t i = 0;
    while (i < sz) {
        size_t bestlen = 0, bestoff = 0;
        if (i > 0) {
            size_t lo = i > 4096 ? i - 4096 : 0;
            size_t j = i - 1;
            if (j >= lo) {
                for (;;) {
                    size_t k = 0;
                    while (i + k < sz && in[j + k] == in[i + k] && k < 256) k++;
                    if (k >= 3 && k > bestlen) { bestlen = k; bestoff = i - j; }
                    if (bestlen >= 256) break;
                    if (j == lo) break;
                    j--;
                }
            }
        }
        if (bestlen >= 3) {
            size_t ln = bestlen;
            if (ln > 256) ln = 256;
            if (ln <= 5 && bestoff <= 256) {
                bwput(&w, 1);
                bwput(&w, 0);
                bwn(&w, (uint32_t)(bestoff - 1), 8);
                bwn(&w, (uint32_t)(ln - 2), 2);
            } else {
                bwput(&w, 1);
                bwput(&w, 1);
                bwn(&w, (uint32_t)(bestoff - 1), 16);
                bwn(&w, (uint32_t)(ln - 1), 8);
            }
            i += ln;
        } else {
            bwput(&w, 0);
            bwn(&w, (uint32_t)in[i], 8);
            i++;
        }
    }
    if (w.nb) w.d[w.len++] = (unsigned char)w.cur;
    fwrite(w.d, 1, w.len, o);
    fclose(o);
    free(in);
    free(data);
    return 0;
}