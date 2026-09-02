#!/usr/bin/env bash
# Oracle for crane-anvil: author the Makefile, build the Fortran tool, and
# sanity-run it on the visible data. Never reads /tests.
set -euo pipefail

cat > /app/Makefile <<'EOF'
FC = gfortran
FFLAGS = -O2 -Wall

.SUFFIXES: .f90 .o

all: avalanche_report

snowmod.o: sources/snowmod.f90
	$(FC) $(FFLAGS) -c $< -o $@

avalanche_report.o: sources/avalanche_report.f90 snowmod.o
	$(FC) $(FFLAGS) -c $< -o $@

avalanche_report: avalanche_report.o snowmod.o
	$(FC) $(FFLAGS) -o $@ avalanche_report.o snowmod.o

clean:
	rm -f *.o *.mod avalanche_report
EOF

cd /app
make -B -f Makefile
/app/avalanche_report /app/data/ridgeline.dat 2.0
echo "solve.sh done"
