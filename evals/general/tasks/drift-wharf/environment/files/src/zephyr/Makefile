# Zephyr compiler build.
#
# Build the single-pass Zephyr compiler (zep) from its C source, then install
# it as /app/cc/bin/cc.  The compiler parses ".zh" source and drives the host
# C toolchain to produce a native executable (or a relocatable object with -c).

CC      ?= gcc
CFLAGS  ?= -O2 -w
PREFIX  ?= /app/cc

.PHONY: all install clean

all: zepc

zepc: zep.c
	$(CC) $(CFLAGS) -o $@ zep.c

install: zepc
	install -d $(PREFIX)/bin
	install -m755 zepc $(PREFIX)/bin/cc
	@echo "Zephyr compiler installed at $(PREFIX)/bin/cc"

clean:
	rm -f zepc