/*
 * flint major-heap sweeping (RUN-LENGTH-COMPRESSED free-space path).
 *
 * Corrected implementation: every maximal run of consecutive dead words
 * becomes exactly one (start, len) run; no run includes a live word or
 * extends past the heap; contiguous free words are always coalesced.
 * The single introduced defect (an off-by-one in the free-run length)
 * is fixed here.
 */
#include "sweep.h"

int sweep(const unsigned char *live, size_t size, run_t *out, size_t capacity) {
    int n = 0;
    unsigned long i = 0;
    while (i < size) {
        if (live[i]) { i++; continue; }
        unsigned long start = i;
        while (i < size && live[i] == 0) i++;      /* stop at first live word */
        unsigned long len = i - start;             /* exact free-run length  */
        if (n < (int)capacity) {
            out[n].start = start;
            out[n].len = len;
            n++;
        }
    }
    return n;
}
