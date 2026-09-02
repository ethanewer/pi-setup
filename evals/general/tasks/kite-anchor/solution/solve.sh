#!/usr/bin/env bash
# kite-anchor oracle: build every deliverable by doing the real work.
set -euo pipefail

cd /app

echo "=== [1/6] cross-compile the MIPS game (game.mips) ==="
mipsel-linux-gnu-gcc -O2 -static -o /app/game.mips /app/sources/hop.c
printf '3 2\n1 5 9\n2 8 4\n' > /tmp/sample_board.txt
echo -n "smoke mips run: "
qemu-mipsel-static /app/game.mips /tmp/sample_board.txt 100

echo "=== [2/6] rewrite fortran build file to gfortran and build /app/main ==="
cat > /app/Makefile <<'MK'
FC      = gfortran
FFLAGS  = -O2

all: main

geom.o: sources/geom.f90
	$(FC) $(FFLAGS) -c sources/geom.f90 -o geom.o

drive.o: sources/drive.f90 geom.o
	$(FC) $(FFLAGS) -c sources/drive.f90 -o drive.o

main: geom.o drive.o
	$(FC) $(FFLAGS) -o main geom.o drive.o
	rm -f geom.o drive.o geom.mod

.PHONY: all clean
MK
make -f /app/Makefile
echo -n "smoke main: "; echo "30 45" | /app/main

echo "=== [3/6] write the polyglot source (poly.c) ==="
cat > /app/poly.c <<'PL'
#include <stdio.h>
int main(void) {
    int a = 0;
    // valid in both C and C++: preprocessor selects the active branch
#ifdef __cplusplus
    a = 1;
#endif
    printf("poly:c=%d\n", a);
    return 0;
}
PL
gcc   -o /tmp/poly_c   /app/poly.c && /tmp/poly_c
g++   -o /tmp/poly_cpp /app/poly.c && /tmp/poly_cpp

echo "=== [4/6] build the C toolkit / sampler (app) ==="
gcc -O2 -o /app/app /app/sources/kite_app.c
echo -n "smoke sample: "; /app/app sample 20 7
echo -n "smoke key:    "; /app/app key 113

echo "=== [5/6] produce /app/key.txt for the official release seeds ==="
: > /app/key.txt
while read -r seed; do
    [ -n "$seed" ] || continue
    code=$(/app/app key "$seed")
    echo "$seed=$code" >> /app/key.txt
done < /app/sources/key_seeds.txt
cat /app/key.txt

echo "=== [6/6] write the Scheme-Lite metacircular evaluator (scheme.py) ==="
cp /solution/scheme.py /app/scheme.py
printf '(+ 1 2)\n(define sq (lambda (x) (* x x)))\n(sq 9)\n' | python3 /app/scheme.py

echo "=== all deliverables built ==="
ls -l /app/game.mips /app/main /app/Makefile /app/poly.c /app/app /app/scheme.py /app/key.txt