#!/bin/bash
# pennant-caboose oracle: fix the XSETID ENTRIESADDED consumer-group clamp
# defect in the real redis tree, install a conforming reproduction script,
# rebuild, and prove the task is passable.
set -eu

SRC=/app/src

# ---- 1. author /app/reproduce.sh (part of the deliverable) ----------------
cp /solution/reproduce.sh /app/reproduce.sh
chmod +x /app/reproduce.sh

# ---- 2. apply the root-cause fix to the source (real work) -----------------
python3 /solution/fix_xsetid.py "$SRC/src/t_stream.c"

# ---- 3. rebuild ------------------------------------------------------------
make -C "$SRC" -j1 > /tmp/oracle-make.log 2>&1
tail -2 /tmp/oracle-make.log

# ---- 4. prove the symptom is gone with the reproduction --------------------
out=$(bash /app/reproduce.sh)
echo "$out"
printf '%s\n' "$out" | grep -q '^VERDICT: FIXED$' \
    || { echo "ORACLE: reproduction did not report FIXED"; exit 1; }

# ---- 5. prove the project's own existing cap-the-value tests stay green ----
( cd "$SRC" && ./runtest --single unit/type/stream-cgroups --only \
    "XGROUP CREATE with ENTRIESREAD larger than stream entries should cap the value" \
    > /tmp/oracle-t1.log 2>&1 )
grep -q "All tests passed" /tmp/oracle-t1.log || { tail -8 /tmp/oracle-t1.log; exit 1; }

( cd "$SRC" && ./runtest --single unit/type/stream-cgroups --only \
    "XGROUP SETID with ENTRIESREAD larger than stream entries should cap the value" \
    > /tmp/oracle-t2.log 2>&1 )
grep -q "All tests passed" /tmp/oracle-t2.log || { tail -8 /tmp/oracle-t2.log; exit 1; }

echo "ORACLE OK: fix applied, reproduction FIXED, existing cap tests green"