/*
 * cardinal.h - Cardinal runtime compatibility header.
 *
 * This header is part of the Cardinal toolchain public interface.  It must
 * compile cleanly BOTH as plain C (the deck sources) AND as a strict C++11
 * translation unit (the probe).  Keep it free of C-only idioms.
 */
#ifndef CARDINAL_H
#define CARDINAL_H

#define CARDINAL_LITERAL_MSK  0x7Fu  /* low 7 bits select a frame payload   */
#define CARDINAL_LITERAL_MAX  128u   /* longest literal frame, in bytes     */

/* A Cardinal stamp: opaque bookkeeping used by the pipeline. */
typedef struct cardinal_seal {
    unsigned long block_id;
    unsigned long span;
} cardinal_seal;

#endif /* CARDINAL_H */