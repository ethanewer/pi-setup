#!/bin/bash
# Helper for the ingot-flood task.
#
# Usage:
#   run_demo.sh [make arguments...]
#
# Builds the repaired tree in /app/src/linuxdoom-1.10 (forwarding any make
# arguments, e.g. CFLAGS=... overrides), then plays the pre-generated demo
# fixture under Xvfb headlessly. Look for the game's own self-test line:
#
#   Error: timed <N> gametics in <M> realtics
#
# That line is the deliverable's proof of life: the engine booted, loaded
# the IWAD and the level, played every tic of the recorded demo and stopped
# at the demo terminator. The process exits 255 (the game's own
# I_Error/exit(-1) path) - that exit code is EXPECTED and is not a failure
# signal; the timing line is.
set -u

SRC=/app/src/linuxdoom-1.10
BIN="$SRC/linux/linuxxdoom"
FIX=/app/fixtures

[ -d "$SRC" ] || { echo "no $SRC"; exit 2; }
[ -f "$FIX/doom1.wad" ] || { echo "no fixture at $FIX (run: python3 /app/genwad.py /app/fixtures 100 d1)"; exit 2; }
. "$FIX/params.env" 2>/dev/null || DEMO=d1

cd "$SRC" || exit 2
mkdir -p linux
echo "== building: make $* =="
make "$@" || { echo "BUILD FAILED"; exit 2; }

cd "$FIX" || exit 2
echo "== playing demo $DEMO =="
DOOMWADDIR="$FIX" xvfb-run -a -s "-screen 0 320x200x8" \
  "$BIN" -timedemo "$DEMO" -nodraw -noblit 2>&1
true