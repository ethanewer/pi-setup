#!/usr/bin/env bash
# Oracle for jib-stave. Runs the real solver (solution/solver.py) against the
# workspace at /app; the solver rebuilds the package manifests from the
# committed lockfile, re-points published entrypoints at the build output,
# removes stale packaged artifacts, and drives the full acceptance sequence.
# It never reads /tests and never hardcodes a precomputed answer.
set -eu

: /app                                        # sanity, also referenced below
root=/app
python3 /solution/solver.py "$root"

# The deliverables this oracle creates/restores (solver.py did the work):
#   /app/package.json
#   /app/packages/core/package.json
#   /app/packages/scale/package.json
#   /app/packages/api/package.json
#   /app/packages/api/dist/index.d.ts          (emitted by npm run build -ws)
for f in \
  /app/package.json \
  /app/packages/core/package.json \
  /app/packages/scale/package.json \
  /app/packages/api/package.json; do
  [ -f "$f" ] || { echo "oracle missing $f" >&2; exit 1; }
done
[ -f /app/packages/api/dist/index.d.ts ] || { echo "oracle missing /app/packages/api/dist/index.d.ts" >&2; exit 1; }

echo "oracle: jibblin monorepo repaired and acceptance sequence green"