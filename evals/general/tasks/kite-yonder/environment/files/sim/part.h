/* Shared physics constants for the Ring-sim. Included by both the serial
 * (part.c) and OpenMP (part_omp.c) builds. */
#ifndef RING_PART_H
#define RING_PART_H

/* coupling, linear damping coefficient, velocity friction */
#define RK_COUPLING 0.01
#define RK_DAMPING  0.002
#define RK_FRICTION 0.97
#define RK_STEP     1.0

#endif