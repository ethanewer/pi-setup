# DOOM-style frame generator for the MIPS port.
# Target ABI manifest: see tools/abi.txt (authoritative).
#
#   make          -> cross-compile gfx/draw.c into out.elf
#   make run      -> cross-compile, then run out.elf under the supplied VM
#                    runner (node tools/run.js) and capture its stdout into out.dat
#
# IMPORTANT: for the required target ABI the toolchain prefix below must match
# the endianness (and ABI) documented in tools/abi.txt.  As shipped, the wrong
# prefix is set on purpose.
TARGET  = mipsel-linux-gnu
CC      = $(TARGET)-gcc
CFLAGS  = -O2 -static
OUT     = out.elf

all: $(OUT)

$(OUT): gfx/draw.c
	$(CC) $(CFLAGS) -o $@ $<

run: $(OUT)
	node tools/run.js $(OUT) > out.dat

clean:
	rm -f $(OUT) out.dat

.PHONY: all run clean