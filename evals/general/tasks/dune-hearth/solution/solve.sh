#!/usr/bin/env bash
# dune-hearth oracle: author the full build project from scratch in /app,
# build it, install prog on PATH, and produce the zstd GNU tar archive.
set -euo pipefail
cd /app

mkdir -p src bin dist

# ----- serial program source (also the OpenMP source) -------------------- #
cat > src/prog.c <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

#define MAXN 262144

static const char *skip_ws(const char *s) {
    while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') s++;
    return s;
}

/* parse exactly one numeric token occupying the whole (trimmed) line */
static int parse_token(const char *line, double *out) {
    const char *p = skip_ws(line);
    if (*p == '\0') return 0;            /* blank line */
    char *end;
    double v = strtod(p, &end);
    if (end == p) return 0;              /* nothing numeric */
    const char *q = skip_ws(end);
    if (*q != '\0') return 0;            /* trailing junk */
    *out = v;
    return 1;
}

/* returns count read, or -1 if the file cannot be opened */
static int read_nums(const char *path, double *buf) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    int n = 0;
    char line[4096];
    while (n < MAXN && fgets(line, sizeof line, f)) {
        if (parse_token(line, &buf[n])) n++;
    }
    fclose(f);
    return n;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: prog <weights-path> <sample-path>\n");
        return 1;
    }
    double *w = malloc(sizeof(double) * MAXN);
    double *s = malloc(sizeof(double) * MAXN);
    if (!w || !s) { free(w); free(s); return 1; }

    int nw = read_nums(argv[1], w);
    int ns = read_nums(argv[2], s);
    if (nw < 0 || ns < 0) {
        fprintf(stderr, "prog: cannot open input file\n");
        free(w); free(s);
        return 1;
    }

    int n = (nw < ns) ? nw : ns;
    double r = 0.0;
#ifdef _OPENMP
#pragma omp parallel for reduction(+:r)
#endif
    for (int i = 0; i < n; i++) r += w[i] * s[i];
    printf("%.3f\n", r);

    free(w); free(s);
    return 0;
}
C

# ----- MPI program source ------------------------------------------------ #
cat > src/mpi_main.cpp <<'CPP'
#include <mpi.h>
#include <cstdio>
#include <cstdlib>
int main(int argc, char **argv) {
    int rank = 0, size = 1;
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    std::printf("rank %d of %d\n", rank, size);
    MPI_Finalize();
    return (rank == 0) ? 0 : EXIT_SUCCESS;
}
CPP

# ----- CMake project ----------------------------------------------------- #
cat > CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(dune_hearth_serial C)
add_executable(prog src/prog.c)
CMAKE

# ----- Makefile ---------------------------------------------------------- #
cat > /app/Makefile <<'MK'
CC := gcc
CXX := mpicxx
CFLAGS := -O2 -Wall
BIN := bin
SRC := src/prog.c
MPI_SRC := src/mpi_main.cpp

.PHONY: all clean selftest

all: $(BIN)/prog $(BIN)/prog_omp $(BIN)/prog_mpi

$(BIN):
	mkdir -p $(BIN)

$(BIN)/prog: $(SRC) | $(BIN)
	$(CC) $(CFLAGS) -o $@ $<

$(BIN)/prog_omp: $(SRC) | $(BIN)
	$(CC) $(CFLAGS) -fopenmp -o $@ $<

$(BIN)/prog_mpi: $(MPI_SRC) | $(BIN)
	$(CXX) $(CFLAGS) -o $@ $<

clean:
	rm -rf $(BIN)

selftest: all
	printf '2\n3\n' > /tmp/home_hearth_sw.dat
	printf '5\n7\n' > /tmp/home_hearth_si.dat
	./$(BIN)/prog /tmp/home_hearth_sw.dat /tmp/home_hearth_si.dat > /tmp/home_hearth_so.txt
	printf '31.000\n' > /tmp/home_hearth_want.txt
	cmp -s /tmp/home_hearth_so.txt /tmp/home_hearth_want.txt
	@echo 'SENTINEL=dune-hearth-ok'
MK

# ----- build orchestrator (deliverable) ---------------------------------- #
cat > /app/build.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd /app
make clean >/dev/null 2>&1 || true
make >/dev/null
install -m 0755 /app/bin/prog /usr/local/bin/prog
mkdir -p /app/dist
tar --zstd -cf /app/dist/dune-hearth-src.tar.zst \
    -C /app \
    CMakeLists.txt Makefile build.sh src
echo "built; prog at /usr/local/bin/prog; archive at /app/dist/dune-hearth-src.tar.zst"
SH
chmod +x /app/build.sh

# ----- execute the real work --------------------------------------------- #
bash /app/build.sh

# sanity: bare invocation from another directory
(cd /tmp && printf '1\n2\n' > hw.dat && printf '3\n4\n' > hs.dat && prog hw.dat hs.dat) | grep -q '^11.000$'
echo "oracle success"
