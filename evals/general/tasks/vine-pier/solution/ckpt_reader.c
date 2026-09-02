/* vine-pier ckpt_reader.c -- dependency-free reader for the lab's bespoke
 * transformer checkpoint and its byte-pair vocabulary.
 *
 * Usage:  ckpt_reader <checkpoint.ckpt> <vocab.txt>
 *
 * Parses the custom little-endian checkpoint format (see instruction.md) and
 * the tab-separated vocabulary, then prints a deterministic report to stdout:
 *   REV <hex>                 revision bytes, hex-encoded
 *   VSIZE <n>                 vocabulary size
 *   MAXGEN <n>
 *   CKPT <name> dtype=<d> ndim=<k> [<dim...>] nelems=<e> fn=<fnv1a64>
 *   ---
 *   TOK <id> <token>          one per vocabulary entry (id ascending)
 * The tests diff this stdout byte-for-byte against a reference implementation,
 * so every field must be exact.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t fnv1a64(const unsigned char *buf, size_t len) {
    uint64_t h = 14695981039346656037ULL;
    size_t i;
    for (i = 0; i < len; i++) {
        h ^= buf[i];
        h *= 1099511628211ULL;
    }
    return h;
}

static uint32_t peek_u32(const unsigned char *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static size_t readall(const char *path, unsigned char **out) {
    FILE *f = fopen(path, "rb");
    unsigned char *buf;
    long n;
    size_t got;
    if (!f) return 0;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return 0; }
    n = ftell(f);
    if (n < 0) { fclose(f); return 0; }
    rewind(f);
    buf = malloc((size_t)n ? (size_t)n : 1);
    if (!buf) { fclose(f); return 0; }
    got = fread(buf, 1, (size_t)n, f);
    fclose(f);
    if (got != (size_t)n) { free(buf); return 0; }
    *out = buf;
    return (size_t)n;
}

int main(int argc, char **argv) {
    unsigned char *buf = NULL;
    unsigned char *p;
    size_t len;
    uint32_t vocab_size, n_tensors, max_gen, d_emb, rev_len;
    uint32_t i, t;
    char rev[512];

    if (argc != 3) {
        fprintf(stderr, "usage: ckpt_reader <checkpoint.ckpt> <vocab.txt>\n");
        return 2;
    }
    len = readall(argv[1], &buf);
    if (!buf || len < 28 || memcmp(buf, "VINER1", 6) != 0) {
        fprintf(stderr, "bad magic\n");
        free(buf);
        return 1;
    }
    p = buf + 8;
    vocab_size = peek_u32(p); p += 4;
    n_tensors = peek_u32(p); p += 4;
    max_gen = peek_u32(p); p += 4;
    d_emb = peek_u32(p); p += 4;
    rev_len = peek_u32(p); p += 4;
    if ((size_t)(p - buf) + rev_len > len || rev_len > sizeof(rev) - 1) {
        fprintf(stderr, "bad revision\n");
        free(buf);
        return 1;
    }
    memcpy(rev, p, rev_len); rev[rev_len] = '\0';
    p += rev_len;

    printf("REV ");
    for (i = 0; i < rev_len; i++) printf("%02x", (unsigned char)rev[i]);
    printf("\nVSIZE %u\nMAXGEN %u\n", vocab_size, max_gen);

    for (t = 0; t < n_tensors; t++) {
        uint32_t name_len, dims[8], nelems = 1, *dimptr;
        unsigned char dtype, nd, j;
        const unsigned char *name, *data;
        size_t data_len;

        if ((size_t)(p - buf) + 4 > len) { fprintf(stderr, "truncated\n"); free(buf); return 1; }
        name_len = peek_u32(p); p += 4;
        if ((size_t)(p - buf) + name_len > len) { fprintf(stderr, "bad name\n"); free(buf); return 1; }
        name = p; p += name_len;
        if ((size_t)(p - buf) + 2 > len) { fprintf(stderr, "bad dtype\n"); free(buf); return 1; }
        dtype = *p++;
        nd = *p++;
        for (j = 0; j < nd; j++) {
            if ((size_t)(p - buf) + 4 > len) { fprintf(stderr, "bad dims\n"); free(buf); return 1; }
            dims[j] = peek_u32(p); p += 4;
            nelems *= dims[j];
        }
        data_len = (size_t)nelems * 4;
        if (p + data_len > buf + len) { fprintf(stderr, "bad data\n"); free(buf); return 1; }
        data = p; p += data_len;

        printf("CKPT %.*s dtype=%u ndim=%u [", (int)name_len, name, dtype, nd);
        for (j = 0; j < nd; j++) {
            if (j) putchar(' ');
            printf("%u", dims[j]);
        }
        printf("] nelems=%u fn=%016llx\n", nelems,
               (unsigned long long)fnv1a64(data, data_len));
    }

    printf("---\n");

    {
        FILE *f = fopen(argv[2], "r");
        char line[1024];
        if (!f) { fprintf(stderr, "vocab open fail\n"); free(buf); return 1; }
        while (fgets(line, sizeof line, f)) {
            char *tab = strchr(line, '\t');
            char *tok, *nl;
            if (!tab) continue;
            *tab = '\0';
            tok = tab + 1;
            nl = strchr(tok, '\n');
            if (nl) *nl = '\0';
            printf("TOK %d %s\n", atoi(line), tok);
        }
        fclose(f);
    }

    free(buf);
    return 0;
}