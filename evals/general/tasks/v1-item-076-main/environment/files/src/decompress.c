/* item-076-main oracle decoder: byte-level LZ77-ish format ("cnt8").
   Reads a compressed file path (argv[1]), writes decompressed bytes to stdout.
   Header: 2-byte little-endian N = total decompressed byte count.
   Body tokens until N bytes produced:
     c <= 0x7F : literal run. count = (c & 0x7F) + 1 (1..128); that many literal
                 bytes follow verbatim.
     c >= 0x80 : back-reference run. count = (c & 0x7F) + 1 (1..128);
                 a 2-byte little-endian offset follows; copy `count` bytes
                 (overlapping allowed) from (current_end - offset).
   This file is compiled into the oracle binary at build time, then removed. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    if (fseek(f, 0, SEEK_END)) return 1;
    long s = ftell(f);
    if (fseek(f, 0, SEEK_SET)) return 1;
    size_t sz = s < 0 ? 0 : (size_t)s;
    unsigned char *in = (unsigned char *)malloc(sz ? sz : 1);
    if (!in) return 1;
    if (sz && fread(in, 1, sz, f) != sz) { free(in); return 1; }
    fclose(f);
    if (sz < 2) { free(in); return 1; }
    size_t n = (size_t)(in[0] | ((size_t)in[1] << 8));
    size_t cap = n + 512; /* a little headroom for malformed inputs */
    unsigned char *out = (unsigned char *)malloc(cap ? cap : 1);
    if (!out) { free(in); return 1; }
    size_t oi = 0, p = 2;
    while (oi < n) {
        if (p >= sz) goto fail;
        unsigned char c = in[p++];
        if ((c & 0x80) == 0) {
            size_t cnt = (size_t)(c & 0x7F) + 1;
            if (p + cnt > sz) goto fail;
            memcpy(out + oi, in + p, cnt);
            p += cnt;
            oi += cnt;
        } else {
            size_t cnt = (size_t)(c & 0x7F) + 1;
            if (p + 2 > sz) goto fail;
            size_t off = (size_t)(in[p] | ((size_t)in[p + 1] << 8));
            p += 2;
            if (off < 1 || off > oi) goto fail;
            for (size_t k = 0; k < cnt; k++) { out[oi] = out[oi - off]; oi++; }
        }
    }
    fwrite(out, 1, oi, stdout);
    free(in);
    free(out);
    return 0;
fail:
    free(in);
    free(out);
    return 1;
}