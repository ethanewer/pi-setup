#!/bin/bash
# Oracle solution for item-041-hard.
# Fixes the two (deliberate) defects, rebuilds, re-runs, and leaves the
# correct artifacts in /app.
set -euo pipefail

cd /app

# Fix 1: target ABI -> big-endian MIPS toolchain prefix (mips-linux-gnu).
sed -i 's/TARGET  *= *mipsel-linux-gnu/TARGET  = mips-linux-gnu/' Makefile

# Fix 2: renderer inner loop must fill all W columns (x < W).
sed -i 's/for (x = 0; x < W - 1; x++)/for (x = 0; x < W; x++)/' doom/frame.c

# Rebuild from scratch and run the pipeline through the runner.
make clean >/dev/null 2>&1 || true
make >/dev/null
make run >/dev/null 2>run.log

# Assertions for the oracle.
test -f /app/out.elf
test -f /app/out.dat
size=$(wc -c < /app/out.dat)
test "$size" = "2054"
hash=$(python3 -c "import hashlib;print(hashlib.sha256(open('/app/out.dat','rb').read()).hexdigest())")
test "$hash" = "7a8e00efcf4625b02cff2c49a58a81a48ffbe67eee843e3a25f36ff2b100ac9a"

echo "item-041-hard solved: out.dat sha256=$hash ($size bytes)"