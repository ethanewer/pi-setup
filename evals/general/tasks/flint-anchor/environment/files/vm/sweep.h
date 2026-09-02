#ifndef FLINT_VM_SWEEP_H
#define FLINT_VM_SWEEP_H

#include <stddef.h>

/* A contiguous run of free words in the major heap, expressed as a
 * start offset and a length (both in heap words). The whole free set is
 * kept as a sorted, disjoint, run-length-encoded (RLE) list of these runs:
 * consecutive free words MUST always be coalesced into a single run. */
typedef struct {
    unsigned long start;
    unsigned long len;
} run_t;

/* Major-heap sweeping.
 *
 *   live    : byte-array of length `size`; live[i] != 0 iff heap word i is
 *             in use after tracing.
 *   size    : number of words in the heap.
 *   out     : caller-provided array that receives the swept free runs.
 *   capacity: number of run_t slots available in `out`.
 *
 * Returns the number of runs written to `out` (never more than `capacity`).
 * The free runs must cover exactly the words with live[i]==0, be ordered by
 * start, be disjoint, never extend past the heap (start+len <= size), and
 * never include a live word. Contiguous free words must appear as ONE run.
 */
int sweep(const unsigned char *live, size_t size, run_t *out, size_t capacity);

#endif
