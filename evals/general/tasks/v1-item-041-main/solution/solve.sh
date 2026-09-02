#!/bin/bash
# Oracle for item-041-main.
# Repairs the two (intentional) defects, rebuilds from scratch, re-runs, and
# leaves the correct artifacts in /app.
set -uo pipefail

cd /app

# Fix 1: target ABI -> big-endian MIPS toolchain prefix (mips-linux-gnu).
sed -i 's/^TARGET  *= *mipsel-linux-gnu$/TARGET  = mips-linux-gnu/' Makefile

# Fix 2: rasterizer inner loop must fill all W columns (x < W).
sed -i 's/for (x = 0; x < W - 1; x++)/for (x = 0; x < W; x++)/' gfx/draw.c

# Rebuild from scratch and run the whole pipeline through the Node.js runner.
make clean >/dev/null 2>&1 || true
make >/dev/null
make run >/dev/null 2>run.log

# Assertions for the oracle.
test -f /app/out.elf
test -f /app/out.dat
size=$(wc -c < /app/out.dat)
test "$size" = "1542"
hash=$(python3 -c "import hashlib;print(hashlib.sha256(open('/app/out.dat','rb').read()).hexdigest())")
test "$hash" = "f84539f45492d43030fbb741f8dc281145d28f6be9665c2e9b1104c778126688"

echo "item-041-main solved: out.dat sha256=$hash ($size bytes)"