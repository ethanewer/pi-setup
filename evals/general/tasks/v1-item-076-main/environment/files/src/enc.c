/* item-076-main encoder ("cnt8" format). Reads plaintext argv[1], writes
   compressed bytes to argv[2]. Greedy: emit a back-reference for any
   self-match of length >= 3 within a 4096-byte window; otherwise emit a
   single-literal run. Produces streams the sibling decompress.c decodes. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    if (fseek(f, 0, SEEK_END)) return 1;
    long s = ftell(f);
    if (fseek(f, 0, SEEK_SET)) return 1;
    if (s < 0 || s > 0xFFFF) { fclose(f); return 1; }
    size_t sz = (size_t)s;
    unsigned char *in = (unsigned char *)malloc(sz ? sz : 1);
    if (!in) return 1;
    if (fread(in, 1, sz, f) != sz) return 1;
    fclose(f);
    FILE *o = fopen(argv[2], "wb");
    if (!o) return 1;
    unsigned char hdr[2] = { (unsigned char)(sz & 255), (unsigned char)((sz >> 8) & 255) };
    fwrite(hdr, 1, 2, o);
    size_t i = 0;
    while (i < sz) {
        size_t bestlen = 0, bestoff = 0;
        if (i > 0) {
            size_t lo = i > 4096 ? i - 4096 : 0;
            size_t j = i - 1;
            if (j >= lo) {
                for (;;) {
                    size_t k = 0;
                    while (i + k < sz && in[j + k] == in[i + k] && k < 128) k++;
                    if (k >= 3 && k > bestlen) { bestlen = k; bestoff = i - j; }
                    if (bestlen >= 128) break;
                    if (j == lo) break;
                    j--;
                }
            }
        }
        if (bestlen >= 3 && bestoff >= 1 && bestoff <= 65535) {
            size_t ln = bestlen;
            if (ln > 128) ln = 128;
            unsigned char c = (unsigned char)(0x80 + (ln - 1));
            fwrite(&c, 1, 1, o);
            unsigned char ob[2] = { (unsigned char)(bestoff & 255), (unsigned char)((bestoff >> 8) & 255) };
            fwrite(ob, 1, 2, o);
            i += ln;
        } else {
            unsigned char c = 0;
            fwrite(&c, 1, 1, o);
            fwrite(in + i, 1, 1, o);
            i++;
        }
    }
    fclose(o);
    free(in);
    return 0;
}