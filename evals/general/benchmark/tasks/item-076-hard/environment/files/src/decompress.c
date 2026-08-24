/* item-076-hard oracle decoder: bit-level LZ77-ish format ("pkb").
   Reads a compressed file path (argv[1]), writes decompressed bytes to stdout.
   Header: 4-byte little-endian N = total decompressed byte count.
   Then a bitstream packed LSB-first within each byte:
     token header bit t:
       0  -> LITERAL: read 8 bits -> one output byte.
       1  -> next header bit s:
            0  -> SHORT back-reference: read 8 bits = off8 (0..255), then 2 bits
                  = len2; offset = off8 + 1; length = len2 + 2 (2..5). Copy
                  length bytes (overlapping) from (end - offset).
            1  -> LONG back-reference: read 16 bits = off16, then 8 bits = len8;
                  offset = off16 + 1; length = len8 + 1 (1..256).
                  Copy length bytes (overlapping) from (end - offset).
   Stop once N bytes are produced (ignore trailing padding bits/bytes).
   This file is compiled into the oracle binary at build time, then removed. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

struct BR { const unsigned char *buf; size_t len, idx; unsigned int cur, nb; };

static int brbit(struct BR *r) {
    if (r->nb == 0) {
        if (r->idx >= r->len) return -1;
        r->cur = r->buf[r->idx++];
        r->nb = 8;
    }
    int v = (int)(r->cur & 1u);
    r->cur >>= 1;
    r->nb--;
    return v;
}

static int brgetn(struct BR *r, int n, uint32_t *out) {
    uint32_t v = 0;
    for (int k = 0; k < n; k++) {
        int b = brbit(r);
        if (b < 0) return 0;
        if (b) v |= (1u << k);
    }
    *out = v;
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    if (fseek(f, 0, SEEK_END)) return 1;
    long s = ftell(f);
    if (fseek(f, 0, SEEK_SET)) return 1;
    size_t sz = s < 0 ? 0 : (size_t)s;
    unsigned char *bin = (unsigned char *)malloc(sz ? sz : 1);
    if (!bin) return 1;
    if (sz && fread(bin, 1, sz, f) != sz) { free(bin); return 1; }
    fclose(f);
    if (sz < 4) { free(bin); return 1; }
    uint32_t n = (uint32_t)bin[0] | ((uint32_t)bin[1] << 8) |
                 ((uint32_t)bin[2] << 16) | ((uint32_t)bin[3] << 24);
    size_t cap = (size_t)n + 512;
    unsigned char *out = (unsigned char *)malloc(cap ? cap : 1);
    if (!out) { free(bin); return 1; }
    struct BR r;
    r.buf = bin;
    r.len = sz;
    r.idx = 4;
    r.cur = 0;
    r.nb = 0;
    size_t oi = 0;
    while (oi < n) {
        int t = brbit(&r);
        if (t < 0) goto fail;
        if (t == 0) {
            uint32_t v;
            if (!brgetn(&r, 8, &v)) goto fail;
            out[oi++] = (unsigned char)v;
        } else {
            int sb = brbit(&r);
            if (sb < 0) goto fail;
            if (sb == 0) {
                uint32_t o8, l2;
                if (!brgetn(&r, 8, &o8) || !brgetn(&r, 2, &l2)) goto fail;
                size_t ln = (size_t)l2 + 2;
                size_t off = (size_t)o8 + 1;
                if (off < 1 || off > oi) goto fail;
                for (size_t k = 0; k < ln; k++) { out[oi] = out[oi - off]; oi++; }
            } else {
                uint32_t o16, l8;
                if (!brgetn(&r, 16, &o16) || !brgetn(&r, 8, &l8)) goto fail;
                size_t ln = (size_t)l8 + 1;
                size_t off = (size_t)o16 + 1;
                if (off < 1 || off > oi) goto fail;
                for (size_t k = 0; k < ln; k++) { out[oi] = out[oi - off]; oi++; }
            }
        }
    }
    fwrite(out, 1, oi, stdout);
    free(bin);
    free(out);
    return 0;
fail:
    free(bin);
    free(out);
    return 1;
}