/* beaconpack - reference C implementation (forked/ported by hand).
 *
 * Byte layout:
 *   [0]       0xC5                magic
 *   [1..5]    little-endian u32   uncompressed length
 *   [5..]     run stream: pair (len-1 as u8, value) for each maximal run
 *             of <=255 equal bytes
 *
 * Port this exact behavior to src/lib.rs in the Rust crate.
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

uint8_t *beaconpack_compress(const uint8_t *data, size_t n, size_t *out_len) {
    size_t cap = 5 + ((n / 255UL) + 1UL) * 2UL;
    uint8_t *out = malloc(cap + 1);
    if (!out) return NULL;
    size_t o = 0;
    out[o++] = 0xC5;
    uint32_t l = (uint32_t)n;
    out[o++] = (uint8_t)(l & 0xff);
    out[o++] = (uint8_t)((l >> 8) & 0xff);
    out[o++] = (uint8_t)((l >> 16) & 0xff);
    out[o++] = (uint8_t)((l >> 24) & 0xff);
    size_t i = 0;
    while (i < n) {
        size_t j = i;
        while (j < n && data[j] == data[i] && (j - i) < 255) j++;
        out[o++] = (uint8_t)((j - i) - 1);
        out[o++] = data[i];
        i = j;
    }
    *out_len = o;
    return out;
}

int beaconpack_decompress(const uint8_t *code, size_t clen,
                          uint8_t **data, size_t *n) {
    if (clen < 5 || code[0] != 0xC5) return -1;          /* bad magic */
    uint32_t total = (uint32_t)code[1] | ((uint32_t)code[2] << 8)
                   | ((uint32_t)code[3] << 16) | ((uint32_t)code[4] << 24);
    uint8_t *out = malloc(total ? total : 1UL);
    if (!out) return -2;
    size_t o = 0, i = 5;
    while (o < (size_t)total) {
        if (i + 1 >= clen) { free(out); return -3; }      /* truncated */
        size_t rlen = (size_t)code[i] + 1UL;
        uint8_t b = code[i + 1];
        i += 2;
        if (o + rlen > (size_t)total) { free(out); return -4; } /* overshoot */
        memset(out + o, b, rlen);
        o += rlen;
    }
    *n = (size_t)total;
    *data = out;
    return 0;
}