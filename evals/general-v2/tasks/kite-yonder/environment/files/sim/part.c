/* Ring-sim SERIAL build (make target: serial)
 * 1-D closed-ring particle simulation. Each of N particles has a scalar
 * position p and velocity v; velocity is pulled toward the local curvature of
 * the ring (coupling) while a linear damping brakes it. Two elementwise
 * passes per step keep every output cell independent so the numerics are
 * identical regardless of how the work is partitioned.
 *
 * usage: serial <N> <steps> <seed>
 * stdout:  init=<ck0> final=<ck1> threads=1 ms=<elapsed>
 * The two checksums are (sum over i of floor(|p_i|*1e6)) modulo 1e9.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include "part.h"

int main(int argc, char **argv){
    if(argc < 4){ fprintf(stderr, "usage: serial <N> <steps> <seed>\n"); return 2; }
    long N = strtol(argv[1], 0, 10), S = strtol(argv[2], 0, 10), seed = strtol(argv[3], 0, 10);
    if(N < 3 || S < 1){ fprintf(stderr, "bad args\n"); return 1; }
    double *p = malloc((size_t)N * sizeof(double));
    double *v = malloc((size_t)N * sizeof(double));
    double *a = malloc((size_t)N * sizeof(double));
    if(!p || !v || !a) return 1;

    for(long i = 0; i < N; i++){
        p[i] = 0.5 + 0.5 * sin(seed + i * 0.71);
        v[i] = 0.05 * cos(seed + i * 1.31);
    }

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for(long s = 0; s < S; s++){
        for(long i = 0; i < N; i++){
            long L = (i + N - 1) % N, R = (i + 1) % N;
            a[i] = RK_COUPLING * ((p[R] - p[i]) - (p[i] - p[L])) - RK_DAMPING * p[i];
        }
        for(long i = 0; i < N; i++){
            v[i] = RK_FRICTION * v[i] + RK_STEP * a[i];
            p[i] += RK_STEP * v[i];
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);

    double init = 0.0, fin = 0.0;
    for(long i = 0; i < N; i++) init += (double)(long long)(fabs(0.5 + 0.5 * sin(seed + i * 0.71)) * 1e6);
    for(long i = 0; i < N; i++) fin  += (double)(long long)(fabs(p[i]) * 1e6);
    double ms = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
    printf("init=%ld final=%ld threads=1 ms=%.2f\n",
           (long)((long long)init % 1000000000L),
           (long)((long long)fin  % 1000000000L), ms);
    free(p); free(v); free(a);
    return 0;
}