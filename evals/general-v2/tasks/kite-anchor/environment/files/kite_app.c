/* kite_app.c — the FK81 particle toolkit + release-code generator, all three
 * operating modes implemented in ONE C source.  Build with:  gcc -O2 -o app
 *
 * MODE "recon"  (CLI particle reconstruction)
 *   app -n <COUNT> -p <POSFILE> -s <SUMFILE> -t <THREADS>
 *     -n  particle count (1..5000)  [required]
 *     -p  path of the position output file                      [required]
 *     -s  path of the summary output file                       [required]
 *     -t  worker threads hint (1..16, output is thread-independent) [required]
 *
 *   The FORWARD output contracts are fully documented in the lab manual:
 *     POSFILE header line:  # i x y z m
 *     then one line per particle i:  i,x,y,z,m   (i = 0..n-1)
 *     where m in {3,4,5,6} is the particle mass.
 *     SUMFILE lines:
 *       count=<n>
 *       total_x=<sum>
 *       total_y=<sum>
 *       total_z=<sum>
 *       extent_x=<max_x-min_x>
 *   stdout line:  particles=<n> sum_x=<sx> sum_y=<sy> threads=<t>
 *
 * MODE "sample":  app sample <LEN> <SEED>
 *   Greedy autoregressive arg-max sampler over a 26-char alphabet
 *   ('a'..'z').  Prints LEN lowercase letters with NO trailing whitespace.
 *
 * MODE "key":     app key <SEED>
 *   Prints the 8-letter activation code for the seed (== sample 8 <SEED>).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* 32-bit unsigned type so every LCG / mask step wraps at 2^32 and matches the
 * reference arithmetic across C, MIPS and Python exactly. */
typedef uint32_t u32;

static u32 lcg(u32 s){ return (u32)((u32)(s * 1664525u) + 1013904223u); }

/* greedy autoregressive arg-max sampler, same algorithm as the Python
 * reference launcher. Returns length LEN string into out (out must hold LEN+1). */
static void sample(u32 seed, unsigned long len, char* out) {
    u32 s = seed & 0xFFFFFFFFu;
    int prev = -1;
    unsigned long t;
    for (t = 0; t < len; t++) {
        s = lcg(s);
        unsigned base = (unsigned)(s % 26u);
        long best = -1;
        long bestsc = -1;
        int tok;
        for (tok = 0; tok < 26; tok++) {
            u32 s2 = lcg((u32)((s ^ ((u32)(tok * 2654435761u))) & 0xFFFFFFFFu));
            long sc = ((long)prev << 3) + tok + 1024L;   /* +1024 keeps num positive so % matches the Python reference */
            long sc2 = (sc * 31L + (long)(s2 & 0xFFu)) % 1000003L;
            if (sc2 > bestsc) { bestsc = sc2; best = tok; }
        }
        out[t] = (char)('a' + best);
        prev = (int)best;
    }
    out[len] = '\0';
}

/* --- recon mode particle generation (deterministic, thread-independent) --- */
#define BASE_SEED 31337u

static void recon(unsigned long n, int threads, const char* posf, const char* sumf) {
    /* We still honor -t by computing a partition plan, but the emitted rows are
     * defined to be independent of threads (documented; thread count only selects
     * an internal worker budget, never the values). */
    long long tx = 0, ty = 0, tz = 0;
    long long mnx = 1LL << 40, mxx = -1, mny = 1LL << 40, mxy = -1,
              mnz = 1LL << 40, mxz = -1;
    unsigned long long mass_sum = 0;
    FILE* pf = fopen(posf, "w");
    unsigned long i;
    if (!pf) { fprintf(stderr, "cannot open posfile\n"); exit(4); }

    fprintf(pf, "# i,x,y,z,m\n");
    for (i = 0; i < n; i++) {
        u32 s = (u32)((BASE_SEED + (u32)(i * 2654435761u)) & 0xFFFFFFFFu);
        s = lcg(s); u32 r0 = s;
        s = lcg(s); u32 r1 = s;
        s = lcg(s); u32 r2 = s;
        s = lcg(s); int m = 3 + (int)((s >> 20) & 3u);
        long long x = (long long)(r0 % 1000000u);
        long long y = (long long)(r1 % 1000000u);
        long long z = (long long)(r2 % 1000000u);
        fprintf(pf, "%llu,%lld,%lld,%lld,%d\n",
                (unsigned long long)i, x, y, z, m);
        tx += x; ty += y; tz += z; mass_sum += (unsigned long long)m;
        if (x < mnx) mnx = x; if (x > mxx) mxx = x;
        if (y < mny) mny = y; if (y > mxy) mxy = y;
        if (z < mnz) mnz = z; if (z > mxz) mxz = z;
    }
    fclose(pf);

    FILE* sf = fopen(sumf, "w");
    if (!sf) { fprintf(stderr, "cannot open sumfile\n"); exit(4); }
    fprintf(sf, "count=%llu\n", (unsigned long long)n);
    fprintf(sf, "mass_sum=%llu\n", mass_sum);
    fprintf(sf, "total_x=%lld\n", tx);
    fprintf(sf, "total_y=%lld\n", ty);
    fprintf(sf, "total_z=%lld\n", tz);
    fprintf(sf, "extent_x=%lld\n", mxx - mnx);
    fprintf(sf, "extent_y=%lld\n", mxy - mny);
    fprintf(sf, "extent_z=%lld\n", mxz - mnz);
    fclose(sf);

    printf("particles=%llu sum_x=%lld sum_y=%lld threads=%d\n",
           (unsigned long long)n, tx, ty, threads);
}

static void usage(void) {
    fprintf(stderr,
        "usage:\n"
        "  app -n COUNT -p POSFILE -s SUMFILE -t THREADS\n"
        "  app sample <LEN> <SEED>\n"
        "  app key   <SEED>\n");
}

int main(int argc, char** argv) {
    if (argc >= 2 && strcmp(argv[1], "sample") == 0) {
        if (argc < 4) { usage(); return 2; }
        unsigned long len = strtoul(argv[2], 0, 10);
        u32 seed = (u32)strtoul(argv[3], 0, 10);
        char buf[65536];
        if (len > 60000) len = 60000;
        sample(seed, len, buf);
        printf("%s\n", buf);
        return 0;
    }
    if (argc >= 2 && strcmp(argv[1], "key") == 0) {
        if (argc < 3) { usage(); return 2; }
        u32 seed = (u32)strtoul(argv[2], 0, 10);
        char buf[9];
        sample(seed, 8, buf);
        printf("%s\n", buf);
        return 0;
    }

    /* recon / CLI mode */
    unsigned long n = 0;
    int threads = 4;
    const char* posf = 0;
    const char* sumf = 0;
    for (int a = 1; a < argc; a++) {
        if (strcmp(argv[a], "-n") == 0 && a + 1 < argc) n = strtoul(argv[++a], 0, 10);
        else if (strcmp(argv[a], "-p") == 0 && a + 1 < argc) posf = argv[++a];
        else if (strcmp(argv[a], "-s") == 0 && a + 1 < argc) sumf = argv[++a];
        else if (strcmp(argv[a], "-t") == 0 && a + 1 < argc) threads = atoi(argv[++a]);
        else { usage(); return 2; }
    }
    if (n == 0 || posf == 0 || sumf == 0 || threads < 1 || threads > 16) {
        usage();
        return 2;
    }
    recon(n, threads, posf, sumf);
    return 0;
}