#!/bin/bash
# Oracle for cedar-canyon. Real work: (1) author the native math stack under
# /app/math (sim.c serial+OpenMP, the fixed natc.c binding, picker.c arg-max
# sampler, port.cpp constexpr port), (2) build binaries + per-TU LLVM IR,
# (3) ship /app/solve.py, (4) run it against the workbench fixture and write
# /app/answer.json. Never reads /tests.
set -eu

MATH=/app/math
mkdir -p "$MATH/src"

# ---------------------------------------------------------------------------
# sim.c  (ONE source -> sim_serial and sim_openmp)
# ---------------------------------------------------------------------------
cat > "$MATH/src/sim.c" <<'EOF'
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double frand(uint64_t *s){
    *s ^= *s << 13; *s ^= *s >> 7; *s ^= *s << 17;
    return (double)((*s >> 11) & 0xFFFFFFu) / (double)(1u << 24) - 0.5;
}
static uint64_t hash64(uint64_t x){
    x ^= x >> 30; x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27; x *= 0x94d049bb133111ebULL;
    x ^= x >> 31; return x;
}

int main(int argc, char **argv){
    if (argc < 5){
        fprintf(stderr, "usage: sim N STEPS SEED OUTFILE\n");
        return 2;
    }
    long N = atol(argv[1]);
    long S = atol(argv[2]);
    uint64_t seed = strtoull(argv[3], NULL, 0);
    const char *outfile = argv[4];

    double *x  = malloc((size_t)N * sizeof(double));
    double *y  = malloc((size_t)N * sizeof(double));
    double *xo = malloc((size_t)N * sizeof(double));
    double *yo = malloc((size_t)N * sizeof(double));
    if (!x || !y || !xo || !yo){ fputs("oom\n", stderr); return 2; }

    uint64_t rs = seed;
    for (long i = 0; i < N; i++){
        xo[i] = x[i] = frand(&rs);
        yo[i] = y[i] = frand(&rs);
    }

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    double wrk = 0.0;
    volatile double sink = 0.0;
    for (long st = 0; st < S; st++){
        double cx = 0.0, cy = 0.0;
        for (long i = 0; i < N; i++){ cx += x[i]; cy += y[i]; }
        cx /= (double)N; cy /= (double)N;
#ifdef _OPENMP
#pragma omp parallel for reduction(+:wrk)
#endif
        for (long i = 0; i < N; i++){
            double dx = cx - x[i], dy = cy - y[i];
            uint64_t h = hash64(seed + (uint64_t)(i + 1) * 0x9E3779B97F4A7C15ULL + (uint64_t)st);
            double px = (double)((h >> 0 ) & 0xFFFFFFu) / (double)(1u << 24) - 0.5;
            double py = (double)((h >> 24) & 0xFFFFFFu) / (double)(1u << 24) - 0.5;
            x[i] += dx * 0.02 + px * 0.001;
            y[i] += dy * 0.02 + py * 0.001;
            double w = x[i] * 0.6180339887498949 + y[i] * 0.3819660112501051;
            for (int k = 0; k < 24; k++){ w = (w * w * 0.5) - w + 0.9; }
            wrk += w;
        }
    }
    sink += wrk;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double secs = (double)(t1.tv_sec - t0.tv_sec) + (double)(t1.tv_nsec - t0.tv_nsec) / 1e9;

    double move = 0.0;
    for (long i = 0; i < N; i++){
        double ddx = x[i] - xo[i], ddy = y[i] - yo[i];
        double d = ddx * ddx + ddy * ddy;
        if (d > move) move = d;
    }
    move = __builtin_sqrt(move);

    uint64_t chk = 0xC0FFEE00DEADBEEFULL;
    for (long i = 0; i < N; i++){
        uint64_t bx; memcpy(&bx, &x[i], 8); chk = hash64(chk ^ bx);
        memcpy(&bx, &y[i], 8); chk = hash64(chk ^ bx);
    }

    printf("TIME %.6f\n", secs);
    printf("MOVE %.9f\n", move);
    printf("SUM %016llx\n", (unsigned long long)chk);
    printf("SINK %.6e\n", (double)sink);
    fflush(stdout);

    FILE *f = fopen(outfile, "w");
    if (f){
        for (long i = 0; i < 8 && i < N; i++) fprintf(f, "%.6f %.6f\n", x[i], y[i]);
        fclose(f);
    }
    free(x); free(y); free(xo); free(yo);
    return 0;
}
EOF

# ---------------------------------------------------------------------------
# natc.c - ctypes prefix-sum binding (FIXED: real running sum)
# ---------------------------------------------------------------------------
cat > "$MATH/src/natc.c" <<'EOF'
/* Native ctypes binding: running (prefix) sum.
 * out[i] = in[0] + ... + in[i] for all i in [0,n); returns n. */
long prefsum(const double *in, long n, double *out){
    double acc = 0.0;
    for (long i = 0; i < n; ++i){
        acc += in[i];
        out[i] = acc;
    }
    return n;
}
EOF

# ---------------------------------------------------------------------------
# picker.c - plain-C arg-max sampler
# ---------------------------------------------------------------------------
cat > "$MATH/src/picker.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
int main(void){
    char line[1 << 16];
    while (fgets(line, sizeof line, stdin)){
        long best = -1; double bv = -1.0; long idx = 0;
        const char *p = line; char *end = NULL;
        while (p && *p){
            double v = strtod(p, &end);
            if (end == p){ p++; continue; }
            if (idx == 0 || v > bv){ bv = v; best = idx; }
            idx++; p = end;
        }
        if (idx == 0) printf("-1\n");
        else printf("%ld\n", best);
    }
    return 0;
}
EOF

# ---------------------------------------------------------------------------
# port.cpp
# ---------------------------------------------------------------------------
cat > "$MATH/src/port.cpp" <<'EOF'
#include <cstdio>
#include <cstddef>
template<size_t N> struct TriSum {
    static constexpr size_t value = N + TriSum<N - 1>::value;
};
template<> struct TriSum<0> { static constexpr size_t value = 0u; };
constexpr size_t clip(size_t n){ return n < 4096 ? n : 4095u; }
int main(){
    constexpr size_t s = TriSum<512>::value;
    std::printf("PORT %zu\n", clip(s));
    return 0;
}
EOF

# ---------------------------------------------------------------------------
# Makefile
# ---------------------------------------------------------------------------
cat > "$MATH/Makefile" <<'EOF'
CC      = gcc
CXX     = g++
CFLAGS  = -O2 -std=c11
CXXFLAGS= -O2 -std=c++14
BIN     = bin

.PHONY: all serial parallel ir clean

all: sim_serial sim_openmp libnatc picker port

$(BIN):
	mkdir -p $(BIN)

sim_serial: $(BIN) src/sim.c
	$(CC) $(CFLAGS) src/sim.c -o $(BIN)/sim_serial -lm

sim_openmp: $(BIN) src/sim.c
	$(CC) $(CFLAGS) -fopenmp src/sim.c -o $(BIN)/sim_openmp -lm

libnatc: $(BIN) src/natc.c
	$(CC) -O2 -shared -fPIC src/natc.c -o $(BIN)/libnatc.so

picker: $(BIN) src/picker.c
	$(CC) -O2 src/picker.c -o $(BIN)/picker

port: $(BIN) src/port.cpp
	$(CXX) $(CXXFLAGS) src/port.cpp -o $(BIN)/port

serial: sim_openmp
	$(BIN)/sim_openmp $(ARGS) /tmp/cedar_serial.csv

parallel: sim_openmp
	$(BIN)/sim_openmp $(ARGS) /tmp/cedar_openmp.csv

ir:
	cmake -S . -B build-emit >/dev/null 2>&1
	cmake --build build-emit --target ir >/dev/null

clean:
	rm -rf $(BIN) build-emit
EOF

# ---------------------------------------------------------------------------
# CMakeLists.txt
# ---------------------------------------------------------------------------
cat > "$MATH/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(cedar_canyon LANGUAGES C CXX)

set(TUS
  ${CMAKE_CURRENT_SOURCE_DIR}/src/sim.c
  ${CMAKE_CURRENT_SOURCE_DIR}/src/natc.c
  ${CMAKE_CURRENT_SOURCE_DIR}/src/picker.c
  ${CMAKE_CURRENT_SOURCE_DIR}/src/port.cpp)

set(IR_DIR ${CMAKE_CURRENT_BINARY_DIR}/ir)
file(MAKE_DIRECTORY ${IR_DIR})

set(IR_TARGETS)
foreach(tu ${TUS})
  get_filename_component(BN ${tu} NAME_WE)
  get_filename_component(EXT ${tu} EXT)
  set(out ${IR_DIR}/${BN}${EXT}.ll)
  if(EXT STREQUAL ".cpp")
    add_custom_command(OUTPUT ${out}
      COMMAND clang++ -std=c++14 -emit-llvm -S ${tu} -o ${out}
      DEPENDS ${tu})
  else()
    add_custom_command(OUTPUT ${out}
      COMMAND clang -std=c11 -emit-llvm -S ${tu} -o ${out}
      DEPENDS ${tu})
  endif()
  list(APPEND IR_TARGETS ${out})
endforeach()

add_custom_target(ir ALL DEPENDS ${IR_TARGETS})
EOF

# ---------------------------------------------------------------------------
# /app/solve.py - the deliverable driver (importable, no side effects)
# ---------------------------------------------------------------------------
cat > /app/solve.py <<'PYEOF'
#!/usr/bin/env python3
"""cedar-canyon driver.

Default        python3 /app/solve.py      build + introspect /app/sample_fixture.
run DIR        python3 /app/solve.py run DIR
"""
import ctypes
import json
import os
import subprocess
import sys

MATH = "/app/math"
BIN = MATH + "/bin"


def _sh(*args, **kw):
    env = dict(os.environ)
    env["OMP_NUM_THREADS"] = "2"  # container is cpus=2; avoid oversubscription
    return subprocess.run(args, capture_output=True, text=True, env=env, **kw)


# ---------------- build ----------------
def build():
    os.makedirs(BIN, exist_ok=True)
    _sh("make", "-C", MATH, "-j4", check=True)


def build_ir():
    _sh("cmake", "-S", MATH, "-B", MATH + "/build-emit", check=True)
    _sh("cmake", "--build", MATH + "/build-emit", "--target", "ir", check=True)


# ---------------- maximal-square (importable, no side effects) --------------
def maximal_square(grid):
    rows = [r for r in grid if r is not None]
    if not rows:
        return 0
    width = min((len(r) for r in rows), default=0)
    if width == 0:
        return 0
    best = 0
    dp = [[0] * width for _ in rows]
    for i, row in enumerate(rows):
        for j in range(width):
            c = row[j]
            v = 1 if c in ("1", 1, True) else 0
            if not v:
                dp[i][j] = 0
                continue
            dp[i][j] = 1 if (i == 0 or j == 0) else \
                min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]) + 1
            if dp[i][j] > best:
                best = dp[i][j]
    return best * best


# ---------------- input readers ----------------
def read_values(fixture):
    p = os.path.join(fixture, "values.txt")
    if not os.path.exists(p):
        return []
    out = []
    with open(p) as fh:
        for line in fh:
            s = line.strip()
            if not s:
                continue
            try:
                out.append(float(s))
            except ValueError:
                continue
    return out


def read_grid(fixture):
    p = os.path.join(fixture, "grid.txt")
    if not os.path.exists(p):
        return []
    rows = []
    with open(p) as fh:
        for line in fh:
            rows.append(line.rstrip("\n"))
    return rows


def read_sim(fixture):
    d = {"N": 40000, "STEPS": 20, "SEED": 7, "BENCHMARK": False}
    p = os.path.join(fixture, "sim.ini")
    if os.path.exists(p):
        with open(p) as fh:
            for line in fh:
                s = line.strip()
                if not s or s.startswith("#") or "=" not in s:
                    continue
                k, v = [x.strip() for x in s.split("=", 1)]
                if k in ("N", "STEPS", "SEED"):
                    try:
                        d[k] = int(v)
                    except ValueError:
                        pass
                elif k == "BENCHMARK":
                    d["BENCHMARK"] = v.strip() == "1"
    d["N"] = max(int(d["N"]), 1)
    d["STEPS"] = max(int(d["STEPS"]), 1)
    return d


def read_weights(fixture):
    p = os.path.join(fixture, "weights.txt")
    if not os.path.exists(p):
        return []
    rows = []
    with open(p) as fh:
        for line in fh:
            row = [float(x) for x in line.split() if x.strip() != ""]
            if row:
                rows.append(row)
    return rows


# ---------------- binding ----------------
def binding_prefix(vals):
    if not vals:
        return []
    lib = ctypes.CDLL(os.path.join(BIN, "libnatc.so"))
    lib.prefsum.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_long,
                            ctypes.POINTER(ctypes.c_double)]
    lib.prefsum.restype = ctypes.c_long
    n = len(vals)
    ina = (ctypes.c_double * n)(*vals)
    outa = (ctypes.c_double * n)()
    lib.prefsum(ina, n, outa)
    return [float(v) for v in outa]


# ---------------- sampler ----------------
def sampler_argmax(weights):
    if not weights:
        return []
    text = "".join(" ".join(map(str, row)) + "\n" for row in weights)
    r = _sh(os.path.join(BIN, "picker"), input=text)
    if r.returncode != 0:
        return []
    toks = []
    for line in r.stdout.splitlines():
        s = line.strip()
        if s != "":
            toks.append(int(s))
    return toks


# ---------------- simulation ----------------
def _run_sim(binary, sim, outcsv):
    r = _sh(binary, str(sim["N"]), str(sim["STEPS"]), str(sim["SEED"]), outcsv)
    d = {"t": None, "move": None, "sum": None}
    if r.returncode != 0:
        return d
    for line in r.stdout.splitlines():
        if line.startswith("TIME"):
            d["t"] = float(line.split()[1])
        elif line.startswith("MOVE"):
            d["move"] = float(line.split()[1])
        elif line.startswith("SUM"):
            d["sum"] = line.split()[1].strip()
    return d


def _median(fn, r=3):
    ts = sorted(fn()["t"] for _ in range(r))
    return ts[len(ts) // 2]


def run_sim(sim, root):
    sbin = os.path.join(BIN, "sim_serial")
    pb = os.path.join(BIN, "sim_openmp")
    sc = os.path.join(root, "cedar_serial.csv")
    oc = os.path.join(root, "cedar_openmp.csv")
    _run_sim(sbin, sim, sc)
    _run_sim(pb, sim, oc)
    st = _median(lambda: _run_sim(sbin, sim, sc))
    pt = _median(lambda: _run_sim(pb, sim, oc))
    ds = _run_sim(sbin, sim, sc)
    do = _run_sim(pb, sim, oc)
    speedup = (st / pt) if (st and pt and pt > 0) else None
    return {
        "serial_s": st,
        "parallel_s": pt,
        "speedup": speedup,
        "move": do["move"],
        "positions_match": bool(ds["sum"] and do["sum"] and ds["sum"] == do["sum"]),
        "serial_move": ds["move"],
    }


# ---------------- llvm ir ----------------
def llvm_ir_files():
    ir = os.path.join(MATH, "build-emit", "ir")
    return [os.path.join(ir, f) for f in [
        "sim.c.ll", "natc.c.ll", "picker.c.ll", "port.cpp.ll"]]


# ---------------- honoured entrypoint ----------------
def run(fixture):
    build()
    build_ir()
    grid = read_grid(fixture)
    vals = read_values(fixture)
    sim = read_sim(fixture)
    sres = run_sim(sim, fixture)
    msq = maximal_square(grid)
    bp = binding_prefix(vals)
    sample_toks = sampler_argmax(read_weights(fixture))
    ans = {
        "task": "cedar-canyon",
        "max_square": msq,
        "binding_prefix": bp,
        "serial_s": sres["serial_s"],
        "parallel_s": sres["parallel_s"],
        "speedup": sres["speedup"],
        "move": sres["move"],
        "positions_match": sres["positions_match"],
        "sampler_argmax": sample_toks,
        "llvm_ir": llvm_ir_files(),
        "ok": True,
    }
    json.dump(ans, open("/app/answer.json", "w"), indent=2)
    return ans


def sample_argmax(weights):
    return sampler_argmax(weights)


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "run":
        run(sys.argv[2])
    else:
        run("/app/sample_fixture")


if __name__ == "__main__":
    main()
PYEOF

chmod +x /app/solve.py

# ---------------------------------------------------------------------------
# Build the stack and produce /app/answer.json
# ---------------------------------------------------------------------------
cd "$MATH"
make -j4 all
make ir
python3 /app/solve.py run /app/sample_fixture
echo "cedar-canyon oracle OK: /app/answer.json written"