#!/bin/bash
# Oracle for gale-quarry: author the simulation source + driver, build both
# binaries, run the visible scenario, and write the report. From a pristine
# container; never reads /tests.
set -eu

mkdir -p /app/src /app/bin

cat > /app/src/motes.c <<'CEOF'
/* gale-quarry: O(n) spatial-binned drifting-mote simulation.
 * One source, two builds: plain (serial) and -fopenmp (parallel for).
 * CLI: motes N STEPS SEED OUTFILE
 * Prints: TIME <sec> / MOVE <max disp> / HASH 0x<16 hex>
 * Writes 2N little-endian doubles (all x then all y) to OUTFILE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <time.h>

#define GRID 64
#define CELLS (GRID * GRID)

static double frac(double v) { return v - floor(v); }

static uint64_t fold(double v, uint64_t h) {
    uint64_t bits;
    memcpy(&bits, &v, sizeof bits);
    h ^= bits;
    h *= 1099511628211ULL;
    return h;
}

int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "usage: motes N STEPS SEED OUTFILE\n");
        return 2;
    }
    long n = atol(argv[1]);
    long steps = atol(argv[2]);
    uint32_t seed = (uint32_t)strtoul(argv[3], NULL, 10);
    const char *outf = argv[4];
    if (n <= 0 || steps < 0) {
        fprintf(stderr, "bad params\n");
        return 2;
    }

    double *x = malloc((size_t)n * sizeof(double));
    double *y = malloc((size_t)n * sizeof(double));
    double *x0 = malloc((size_t)n * sizeof(double));
    double *y0 = malloc((size_t)n * sizeof(double));
    if (!x || !y || !x0 || !y0) { fprintf(stderr, "oom\n"); return 3; }

    /* Deterministic quasicrystal init from SEED. */
    double s1 = frac(0.6180339887498949 * (double)(seed % 100000u));
    double s2 = frac(0.7548776662466927 * (double)((seed * 2654435761u) % 100000u));
    for (long i = 0; i < n; i++) {
        x[i] = frac(s1 + 0.6180339887498949 * (double)i);
        y[i] = frac(s2 + 0.7548776662466927 * (double)i);
    }
    memcpy(x0, x, (size_t)n * sizeof(double));
    memcpy(y0, y, (size_t)n * sizeof(double));

    int *cnt = calloc(CELLS, sizeof(int));
    double *sx = calloc(CELLS, sizeof(double));
    double *sy = calloc(CELLS, sizeof(double));
    double *mx = calloc(CELLS, sizeof(double));
    double *my = calloc(CELLS, sizeof(double));
    if (!cnt || !sx || !sy || !mx || !my) { fprintf(stderr, "oom\n"); return 3; }

    const double dt = 0.01;
    const double pull = 0.05;
    const double swirl = 0.03;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    for (long st = 0; st < steps; st++) {
        memset(cnt, 0, CELLS * sizeof(int));
        for (long c = 0; c < CELLS; c++) { sx[c] = 0.0; sy[c] = 0.0; }
        /* O(n) binning pass: count + centre-of-mass per cell. */
        for (long i = 0; i < n; i++) {
            int cx = (int)(x[i] * GRID); if (cx >= GRID) cx = GRID - 1; if (cx < 0) cx = 0;
            int cy = (int)(y[i] * GRID); if (cy >= GRID) cy = GRID - 1; if (cy < 0) cy = 0;
            int c = cy * GRID + cx;
            cnt[c]++;
            sx[c] += x[i];
            sy[c] += y[i];
        }
        for (long c = 0; c < CELLS; c++) {
            if (cnt[c] > 0) {
                mx[c] = sx[c] / (double)cnt[c];
                my[c] = sy[c] / (double)cnt[c];
            } else {
                mx[c] = 0.0;
                my[c] = 0.0;
            }
        }
        /* O(1) per-particle update; writes are independent per particle. */
#ifdef _OPENMP
#pragma omp parallel for
#endif
        for (long i = 0; i < n; i++) {
            int cx = (int)(x[i] * GRID); if (cx >= GRID) cx = GRID - 1; if (cx < 0) cx = 0;
            int cy = (int)(y[i] * GRID); if (cy >= GRID) cy = GRID - 1; if (cy < 0) cy = 0;
            int c = cy * GRID + cx;
            double px = x[i], py = y[i];
            /* Fixed 24-iteration scalar recurrence; feeds (weakly) into motion. */
            double u = px + py;
            for (int j = 0; j < 24; j++) {
                u = u * 1.0000001 + 0.000013;
            }
            u = u - floor(u);
            double dx = px - mx[c];
            double dy = py - my[c];
            double vx = -pull * dx - swirl * dy;
            double vy = -pull * dy + swirl * dx;
            px += dt * (vx + (u - 0.5) * 1e-9);
            py += dt * vy;
            if (px >= 1.0) px -= 1.0;
            if (px < 0.0) px += 1.0;
            if (py >= 1.0) py -= 1.0;
            if (py < 0.0) py += 1.0;
            x[i] = px;
            y[i] = py;
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (double)(t1.tv_sec - t0.tv_sec) +
                     (double)(t1.tv_nsec - t0.tv_nsec) / 1e9;

    double move = 0.0;
    for (long i = 0; i < n; i++) {
        double dx = fabs(x[i] - x0[i]); if (dx > 0.5) dx = 1.0 - dx;
        double dy = fabs(y[i] - y0[i]); if (dy > 0.5) dy = 1.0 - dy;
        double d = dx > dy ? dx : dy;
        if (d > move) move = d;
    }

    uint64_t h = 1469598103934665603ULL;
    for (long i = 0; i < n; i++) {
        h = fold(x[i], h);
        h = fold(y[i], h);
    }

    printf("TIME %.6f\n", elapsed);
    printf("MOVE %.9f\n", move);
    printf("HASH 0x%016llx\n", (unsigned long long)h);

    FILE *f = fopen(outf, "wb");
    if (!f) { fprintf(stderr, "cannot write %s\n", outf); return 4; }
    fwrite(x, sizeof(double), (size_t)n, f);
    fwrite(y, sizeof(double), (size_t)n, f);
    fclose(f);
    return 0;
}
CEOF

cat > /app/launch.py <<'PEOF'
#!/usr/bin/env python3
"""gale-quarry driver: build both binaries, run a scenario, report JSON.

Usage:
    python3 /app/launch.py            # visible scenario /app/scenario.ini
    python3 /app/launch.py run DIR    # scenario DIR/scenario.ini
"""
import json
import os
import subprocess
import sys

APP = "/app"
SRC = os.path.join(APP, "src", "motes.c")
BIN_S = os.path.join(APP, "bin", "motes_serial")
BIN_O = os.path.join(APP, "bin", "motes_openmp")
RESULT = os.path.join(APP, "result.json")


def build():
    os.makedirs(os.path.join(APP, "bin"), exist_ok=True)
    subprocess.run(["gcc", "-O2", "-o", BIN_S, SRC, "-lm"], check=True,
                   capture_output=True, text=True)
    subprocess.run(["gcc", "-O2", "-fopenmp", "-o", BIN_O, SRC, "-lm"],
                   check=True, capture_output=True, text=True)


def parse_ini(path):
    cfg = {"N": 2000, "STEPS": 20, "SEED": 1, "MOTION": 0}
    with open(path) as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip().upper()
            v = v.strip()
            if k in cfg and v != "":
                try:
                    cfg[k] = int(v)
                except ValueError:
                    pass
    return cfg


def run_one(binary, n, steps, seed, outbin, env=None):
    r = subprocess.run([binary, str(n), str(steps), str(seed), outbin],
                       capture_output=True, text=True, timeout=280, env=env)
    if r.returncode != 0:
        raise RuntimeError("binary failed rc=%d: %s %s" % (r.returncode, r.stdout, r.stderr))
    out = {}
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2:
            out[parts[0]] = parts[1]
    if "HASH" not in out or "MOVE" not in out or "TIME" not in out:
        raise RuntimeError("binary output missing fields: %r" % r.stdout)
    return out


def openmp_linked():
    try:
        r = subprocess.run(["ldd", BIN_O], capture_output=True, text=True)
        return "libgomp" in r.stdout
    except Exception:
        return False


def main():
    args = sys.argv[1:]
    if args and args[0] == "run" and len(args) >= 2:
        ini = os.path.join(args[1], "scenario.ini")
    else:
        ini = os.path.join(APP, "scenario.ini")

    cfg = parse_ini(ini)
    n, steps, seed = cfg["N"], cfg["STEPS"], cfg["SEED"]

    build()
    threads = max(1, min(os.cpu_count() or 2, 8))
    env = dict(os.environ)
    env["OMP_NUM_THREADS"] = str(threads)

    ser = run_one(BIN_S, n, steps, seed, "/tmp/gq_serial.bin")
    par = run_one(BIN_O, n, steps, seed, "/tmp/gq_openmp.bin", env=env)

    match = (ser["HASH"] == par["HASH"]) and (ser["MOVE"] == par["MOVE"])
    linked = openmp_linked()
    move = float(ser["MOVE"])
    result = {
        "task": "gale-quarry",
        "n": n,
        "steps": steps,
        "seed": seed,
        "serial_hash": ser["HASH"],
        "openmp_hash": par["HASH"],
        "match": match,
        "move": move,
        "serial_ms": int(round(float(ser["TIME"]) * 1000)),
        "openmp_ms": int(round(float(par["TIME"]) * 1000)),
        "threads": threads,
        "openmp_linked": linked,
        "ok": bool(match and linked),
    }
    with open(RESULT, "w") as fh:
        json.dump(result, fh, indent=1)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
PEOF
chmod +x /app/launch.py

# Build and run the visible scenario to produce the report deliverable.
python3 /app/launch.py

echo "gale-quarry solve done"
ls -l /app/src/motes.c /app/launch.py /app/result.json /app/bin/motes_serial /app/bin/motes_openmp
