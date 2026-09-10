#!/usr/bin/env bash
# Oracle for cistern-loom: performs the real strict-mode migration of
# /app/cistern.
#
# The migration script is generated from the same corpus that builds the
# fixture, and re-renders every source module with its annotations and
# non-null proofs in place, then commits the hardened strict tsconfig
# (strict, strictNullChecks, noImplicitAny, noUncheckedIndexedAccess,
# exactOptionalPropertyTypes, noImplicitOverride). Finally the reference
# solution reruns the type-check and the vitest suite against the
# migrated tree, the same way the agent must. It never reads /tests.
set -euo pipefail

python3 /solution/migrate.py /app/cistern

cd /app/cistern
test -f /app/cistern/tsconfig.json
test -f /app/cistern/package.json
./node_modules/.bin/tsc --noEmit -p tsconfig.json
./node_modules/.bin/vitest run --reporter=dot >/tmp/cistern-oracle-vitest.log
grep -qE "Test Files .* passed" /tmp/cistern-oracle-vitest.log || {
  echo "oracle: vitest did not pass" >&2
  exit 1
}

echo "oracle complete: /app/cistern migrated to strict mode and green"