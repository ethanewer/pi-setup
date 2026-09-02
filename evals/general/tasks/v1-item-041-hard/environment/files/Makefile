# MIPS cross build for the DOOM-style framebuffer renderer.
# Target ABI manifest: see tools/abi.txt (authoritative).
#
# Current state: the build is BROKEN against the required ABI.
#   `make`          -> cross-compile doom/frame.c into out.elf
#   `make run`      -> cross-compile, then run out.elf through the supplied
#                      VM runner (node tools/run.js) and capture its stdout
#                      into out.dat

# NOTE: for the required target ABI the toolchain prefix must match the
# endianness and ABI specified in tools/abi.txt.
TARGET  = mipsel-linux-gnu
CC      = $(TARGET)-gcc
CFLAGS  = -O2 -static
OUT     = out.elf

all: $(OUT)

$(OUT): doom/frame.c
	$(CC) $(CFLAGS) -o $@ $<

run: $(OUT)
	node tools/run.js $(OUT) > out.dat

clean:
	rm -f $(OUT) out.dat

.PHONY: all run clean