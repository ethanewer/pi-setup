#!/bin/bash
# Prove the shipped repository state has the intended shape:
#   * git history present (7 commits, HEAD is the regression commit)
#   * `npm run build` exits 0 (the packaging is *broken* but still builds)
#   * ... but emits NO ESM artifact and NO type declarations
#   * `npm test` is red (7 failures across the three component specs + others)
set -u
cd /app

fail() { echo "SELFCHECK FAIL: $1" >&2; exit 1; }

[ "$(git rev-list --count HEAD)" = "7" ] || fail "expected 7 commits, got $(git rev-list --count HEAD)"

npm run build >/tmp/selfcheck-build.log 2>&1 || fail "npm run build should exit 0 (packaging regressed but must build)"
[ ! -f dist/marline-lib.mjs ] || fail "shipped state must NOT emit the ESM artifact yet"
[ ! -f dist/index.d.ts ] || fail "shipped state must NOT emit type declarations yet"

set +e
npm test >/tmp/selfcheck-test.log 2>&1
rc=$?
set -e
[ "$rc" != "0" ] || fail "shipped test suite must be red"
grep -qE "[0-9]+ failed" /tmp/selfcheck-test.log || fail "no failing tests reported by vitest"

echo "selfcheck ok: 7 commits, build green/no ESM, suite red"
