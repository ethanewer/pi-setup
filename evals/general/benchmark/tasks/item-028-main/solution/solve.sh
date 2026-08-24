#!/bin/bash
# Oracle solution for item-028-main: fix the signed-count boundary bug, rebuild,
# and confirm a correct round-trip and checksum.
set -euo pipefail
cd /app

# Smallest correct fix: the layout uses u8 counts (1..255), but the C runtime
# reads the run-length byte through a SIGNED char, so counts >= 128 (160,255
# in this stream) are mis-read. Read it as unsigned.
sed -i 's/int count = (signed char) c;/int count = (int)(unsigned char) c;/' runtime.c
# (also normalize the comment above the line so it stays accurate)
sed -i 's/BUG: reads count as signed/BUG was: reads count as signed; now unsigned/' runtime.c

make clean
make runtime          # recompile C runtime
make rcode.dat        # regenerate spec stream deterministically
make check            # run ./runtime
python3 verify.py

echo "SOLVED"