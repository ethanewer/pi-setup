/* brine-mesa reference sim (serial). Used to generate expected outputs and as
 * the oracle baseline. Compiled with -ffp-contract=off to match the spec's
 * operation order exactly. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#ifdef _OPENMP
#include <omp.h>
#endif

static double *px, *py, *pz, *vx, *vy, *vz;
static int N, STEPS;
static double CUTOFF, DT, LX, LY, LZ;
static int ncx, ncy, ncz;
static double hx, hy, hz;
static int *cell_of, *cell_start, *order;

static int cell_idx(int cx, int cy, int cz) {
    return (cz * ncy + cy) * ncx + cx;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: sim REFERENCE INFILE OUTFILE\n");
        return 2;
    }
    FILE *in = fopen(argv[1], "r");
    if (!in || fscanf(in, "%d %lf %lf %d %lf %lf %lf", &N, &CUTOFF, &DT,
                      &STEPS, &LX, &LY, &LZ) != 7) {
        fprintf(stderr, "bad header\n");
        return 2;
    }
    px = malloc(sizeof(double) * N); py = malloc(sizeof(double) * N);
    pz = malloc(sizeof(double) * N); vx = malloc(sizeof(double) * N);
    vy = malloc(sizeof(double) * N); vz = malloc(sizeof(double) * N);
    for (int i = 0; i < N; i++) {
        if (fscanf(in, "%lf %lf %lf %lf %lf %lf", &px[i], &py[i], &pz[i],
                   &vx[i], &vy[i], &vz[i]) != 6) {
            fprintf(stderr, "bad particle line %d\n", i);
            return 2;
        }
    }
    fclose(in);

    ncx = (int)floor(LX / CUTOFF); if (ncx < 1) ncx = 1;
    ncy = (int)floor(LY / CUTOFF); if (ncy < 1) ncy = 1;
    ncz = (int)floor(LZ / CUTOFF); if (ncz < 1) ncz = 1;
    hx = LX / ncx; hy = LY / ncy; hz = LZ / ncz;
    int ncells = ncx * ncy * ncz;
    cell_of = malloc(sizeof(int) * N);
    cell_start = malloc(sizeof(int) * (ncells + 1));
    order = malloc(sizeof(int) * N);

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    double moved = 0.0;
    int max_threads = 1;
    double *fx = calloc(N, sizeof(double));
    double *fy = calloc(N, sizeof(double));
    double *fz = calloc(N, sizeof(double));
    double c2 = CUTOFF * CUTOFF;

    for (int step = 0; step < STEPS; step++) {
        /* counting sort by cell -> cell_start, order (ascending index within
         * each cell) */
        for (int c = 0; c <= ncells; c++) cell_start[c] = 0;
        for (int i = 0; i < N; i++) {
            int cx = (int)(px[i] / hx); if (cx >= ncx) cx = ncx - 1; if (cx < 0) cx = 0;
            int cy = (int)(py[i] / hy); if (cy >= ncy) cy = ncy - 1; if (cy < 0) cy = 0;
            int cz = (int)(pz[i] / hz); if (cz >= ncz) cz = ncz - 1; if (cz < 0) cz = 0;
            int c = cell_idx(cx, cy, cz);
            cell_of[i] = c;
            cell_start[c + 1]++;
        }
        for (int c = 0; c < ncells; c++) cell_start[c + 1] += cell_start[c];
        int *fill = malloc(sizeof(int) * ncells);
        for (int c = 0; c < ncells; c++) fill[c] = cell_start[c];
        for (int i = 0; i < N; i++) order[fill[cell_of[i]]++] = i;
        free(fill);

        /* forces from current positions, then integrate */
        memset(fx, 0, sizeof(double) * N);
        memset(fy, 0, sizeof(double) * N);
        memset(fz, 0, sizeof(double) * N);
#pragma omp parallel
        {
#ifdef _OPENMP
#pragma omp master
            max_threads = omp_get_num_threads() > max_threads ? omp_get_num_threads() : max_threads;
#endif
#pragma omp for schedule(static)
        for (int i = 0; i < N; i++) {
            int cxi = cell_of[i] % ncx;
            int cyi = (cell_of[i] / ncx) % ncy;
            int czi = cell_of[i] / (ncx * ncy);
            for (int dcx = -1; dcx <= 1; dcx++) {
                int cx = ((cxi + dcx) % ncx + ncx) % ncx;
                for (int dcy = -1; dcy <= 1; dcy++) {
                    int cy = ((cyi + dcy) % ncy + ncy) % ncy;
                    for (int dcz = -1; dcz <= 1; dcz++) {
                        int cz = ((czi + dcz) % ncz + ncz) % ncz;
                        int c = cell_idx(cx, cy, cz);
                        for (int k = cell_start[c]; k < cell_start[c + 1]; k++) {
                            int j = order[k];
                            if (j == i) continue;
                            double dx = px[i] - px[j];
                            double dy = py[i] - py[j];
                            double dz = pz[i] - pz[j];
                            dx -= LX * round(dx / LX);
                            dy -= LY * round(dy / LY);
                            dz -= LZ * round(dz / LZ);
                            double r2 = dx * dx + dy * dy + dz * dz;
                            if (r2 < 1e-12 || r2 >= c2) continue;
                            double r = sqrt(r2);
                            double f = (1.0 - r / CUTOFF) / r;
                            fx[i] += f * dx;
                            fy[i] += f * dy;
                            fz[i] += f * dz;
                        }
                    }
                }
            }
        }
        }
#pragma omp parallel for reduction(max:moved)
        for (int i = 0; i < N; i++) {
            double ox = px[i], oy = py[i], oz = pz[i];
            vx[i] += fx[i] * DT;
            vy[i] += fy[i] * DT;
            vz[i] += fz[i] * DT;
            px[i] += vx[i] * DT;
            py[i] += vy[i] * DT;
            pz[i] += vz[i] * DT;
            /* per-step displacement measured BEFORE the periodic wrap */
            double ddx = px[i] - ox, ddy = py[i] - oy, ddz = pz[i] - oz;
            double d = sqrt(ddx * ddx + ddy * ddy + ddz * ddz);
            if (d > moved) moved = d;
            px[i] -= LX * floor(px[i] / LX);
            py[i] -= LY * floor(py[i] / LY);
            pz[i] -= LZ * floor(pz[i] / LZ);
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double seconds = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) * 1e-9;

    FILE *out = fopen(argv[2], "w");
    for (int i = 0; i < N; i++)
        fprintf(out, "%.17g %.17g %.17g\n", px[i], py[i], pz[i]);
    fclose(out);
#ifdef _OPENMP
    printf("threads=%d seconds=%.3f moved=%.6f\n", max_threads, seconds, moved);
#else
    printf("threads=%d seconds=%.3f moved=%.6f\n", 1, seconds, moved);
#endif
    return 0;
}
