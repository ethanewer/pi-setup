/* hop.c — the MIPS "hopping rover" terrain sampler that must be
 * cross-compiled into a little-endian MIPS ELF.
 *
 * Usage:  game.mips <boardfile> <steps>
 *
 * <boardfile> : first line "W H", then W*H integer heights (0..99),
 *               row-major (W columns, H rows).
 * <steps>     : a non-negative integer (>= 0).
 *
 * The rover starts with an accumulator acc = 0 and a 32-bit LCG seed
 * 0x1234567.  For step i in 1..steps it visits the next grid cell in
 * row-major order (cycling if steps exceed the cell count), refreshes
 * the LCG, and folds the height and a slice of the LCG into acc using
 * unsigned 32-bit wraparound arithmetic.
 *
 * stdout: a single line holding the final unsigned 32-bit accumulator.
 */
#include <stdio.h>
#include <stdlib.h>

static unsigned load_board(const char* path, unsigned* cells, unsigned* w, unsigned* h) {
    FILE* f = fopen(path, "r");
    if (!f) return 0;
    int W = 0, H = 0;
    if (fscanf(f, "%d %d", &W, &H) != 2 || W <= 0 || H <= 0) {
        fclose(f);
        return 0;
    }
    unsigned total = (unsigned)(W * H);
    unsigned got = 0;
    for (unsigned i = 0; i < total && !feof(f); i++) {
        int v;
        if (fscanf(f, "%d", &v) == 1) cells[got++] = (unsigned)(v & 0x7f);
    }
    *w = (unsigned)W;
    *h = (unsigned)H;
    fclose(f);
    return got;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: hop <boardfile> <steps>\n");
        return 2;
    }
    unsigned cells[512];
    unsigned W = 0, H = 0;
    unsigned total = load_board(argv[1], cells, &W, &H);
    if (total == 0) {
        fprintf(stderr, "bad board\n");
        return 3;
    }
    long long steps = atoll(argv[2]);
    if (steps < 0) steps = 0;

    unsigned acc = 0u;
    unsigned seed = 0x12345678u;
    for (long long i = 1; i <= steps; i++) {
        seed = seed * 1103515245u + 12345u;               /* uint32 wrap */
        unsigned h = cells[(unsigned)((i - 1) % (long long)total)];
        acc = acc * 33u + h + ((seed >> 16) & 0x7fu);     /* uint32 wrap */
    }
    printf("%u\n", acc);
    return 0;
}