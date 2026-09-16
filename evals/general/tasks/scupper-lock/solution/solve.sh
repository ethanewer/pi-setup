#!/bin/bash
# Oracle for scupper-lock: installs the real component implementation and its
# API reference into /app, then proves them by running the strict type-check
# and the visible vitest suite (jsdom + @testing-library/react). The solver
# never reads /tests and contains no precomputed answer.
set -eu

cp /solution/solve-table.tsx /app/DataTable.tsx
cp /solution/DataTable.md /app/DataTable.md

cd /app
"$PWD/node_modules/.bin/tsc" --noEmit -p tsconfig.json
node node_modules/vitest/vitest.mjs run visible

echo "oracle produced /app/DataTable.tsx and /app/DataTable.md"
echo "oracle visible suite: GREEN"