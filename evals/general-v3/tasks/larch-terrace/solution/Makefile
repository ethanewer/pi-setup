# Retargeted build: same two sources, compiled with gfortran.
# The .f90 sources are left untouched; only the compiler/frontend changed.
FC      = gfortran
FFLAGS  = -O2 -ffree-line-length-none
SRCS    = src/fseries/series_mod.f90 src/fseries/main_series.f90

main: $(SRCS)
	$(FC) $(FFLAGS) -o $@ $(SRCS)

clean:
	rm -f main *.mod

.PHONY: clean
