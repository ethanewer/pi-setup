/*
 * hull/engine.h
 *
 * Public interface of the "hull" reuse engine for the raven-jetty toolchain
 * bench. This is the engine's *public* header: it lives inside the engine
 * include tree, so a translation unit must add the engine include root to the
 * preprocessor search path before it can `#include <hull/engine.h>` with angle
 * brackets.
 *
 * The engine exports three constants and one callback hook. A downstream TU
 * only ever needs the preprocessor macros to pass the toolchain probes.
 */
#ifndef HULL_ENGINE_H
#define HULL_ENGINE_H

#define HULL_LEVEL 9          /* engineered bolt level, fixed */
#define HULL_TAG   "raven-weave"

enum hull_throttle {
    HULL_ROLL  = 0,           /* continuous feed */
    HULL_STITCH = 1,          /* intermittent feed */
    HULL_TAKEOFF = 2          /* cold-start feed */
};

static inline int hull_step(int x) {
    return x * HULL_LEVEL + (int)HULL_ROLL;
}

#endif /* HULL_ENGINE_H */