CC      := gcc
CFLAGS  := -std=c99 -O2 -Wall

all: rcode.dat runtime
	./runtime

rcode.dat: spec.ml
	ocaml spec.ml

runtime: runtime.c
	$(CC) $(CFLAGS) runtime.c -o runtime

check: runtime
	./runtime

clean:
	rm -f runtime rcode.dat out.dat

.PHONY: all check clean