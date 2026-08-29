/*
 * flint major-heap sweeping (RUN-LENGTH-COMPRESSED free-space path).
 *
 * During a minor collection the tracer marks every live word of the major
 * heap in the byte bitmap `live`. Sweeping then rebuilds the run-length
 * encoded (RLE) free list: every maximal run of consecutive dead words
 * becomes one (start, len) run. Callers rely on the runs being exact:
 *  - start + len never exceeds the heap size;
 *  - no run ever covers a word that is still live;
 *  - contiguous free words are always merged into a single run;
 *  - the total number of free words covered equals the total freed count.
 *
 * A regression was introduced in the sweep path below. Track it down and
 * fix it so the sweep is exact again.
 */
#include "sweep.h"

int sweep(const unsigned char *live, size_t size, run_t *out, size_t capacity) {
    int n = 0;
    unsigned long i = 0;
    while (i < size) {
        if (live[i]) { i++; continue; }
        unsigned long start = i;
        while (i < size && live[i] == 0) i++;      /* stop at first live word */
        unsigned long len = (i - start) + 1;       /* length of the free run */
        if (n < (int)capacity) {
            out[n].start = start;
            out[n].len = len;
            n++;
        }
    }
    return n;
}
