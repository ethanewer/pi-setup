#!/bin/bash
# Oracle for pawl-bell: build the real Stockfish engine from the pinned
# checkout with the project's own Makefile, then install the UCI driver as
# the second declared deliverable. It NEVER reads /tests.
#
# The build is the point of the task: the binary must come out of /app/src
# via the upstream build system, and the verifier checks its deterministic
# depth-7 search results directly.
set -euo pipefail

# 1) Build the engine, single-threaded, portable arch profile.
cd /app/src/src
make -j1 build ARCH=x86-64

# 2) Install the driver deliverable.
cp /solution/solver.py /app/uci_play.py
chmod 755 /app/uci_play.py

# 3) Cheap self-check: the driver must run end to end and print the exact
#    output format for a real position (values are checked by the verifier,
#    not here). No /tests involvement.
out=$(python3 /app/uci_play.py "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" 5)
echo "self-check driver output: $out"
if ! printf '%s' "$out" | grep -Eq '^bestmove:[a-h][1-8][a-h][1-8](=[qrbnkQRBNK])? score:(-?[0-9]+|mate-?[0-9]+)$'; then
    echo "oracle self-check failed: unexpected driver output format: $out" >&2
    exit 1
fi

# 4) Both deliverables in place.
test -x /app/src/src/stockfish
test -x /app/uci_play.py
echo "pawl-bell oracle done"