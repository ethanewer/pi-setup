#!/bin/bash
# Oracle for capstan-roadstead: applies the one-source-file fix to the real
# jest tree at /app/src (the glob-matcher cache must only be consulted and
# populated for calls that pass no options; whenever options are given, a
# fresh matcher is built with those options and the dot default of true is
# preserved when dot is explicitly undefined), writes /app/summary.md, then
# proves the work with the project's own machinery: /app/repro.sh must
# print 'true false' and exit 0, and the project's own regression test for
# the bug (baked at /opt/golden) must pass 10/10 under the published jest
# runner when compiled against the repaired tree sources. The golden file
# is only copied into a scratch layout, never into /app/src, so the tree
# stays exactly as the verifier expects it.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied option-aware matcher cache fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: file-selection behavior that depends on glob-matching options silently
stopped working after the first time a pattern was seen. Matchers were
cached in a module-level map keyed on the glob string alone, so a glob
first compiled with one option set (for example dotfile matching on by
default) kept behaving that way for every later call in the same process,
even when different options such as `{dot: false}` were passed. Patterns
used for excluding or including files therefore matched stale sets,
depending on call order.

Cause: the matcher cache was consulted and populated unconditionally,
without considering the per-call `picomatchOptions` argument, and the
default `dot` value was spread in front of the caller's options.

Fix: cache only calls that pass no options. When `picomatchOptions` is
undefined, the cache is used and populated as before. Whenever options are
given, a fresh picomatch matcher is built with exactly those options (with
the dot default of true applied after the spread, so an explicitly
`undefined` dot still means "match dotfiles by default"). Individual calls
now behave like the micromatch package, and option-less calls keep the
cache benefit.

Verification: `/app/repro.sh` prints `true false` and exits 0; the
project's own regression test for this behavior (the upstream extension of
`globsToMatcher.test.ts`, 10 cases) passes 10/10 under jest against the
repaired tree; the project's own pre-existing jest-util tests
(`isPromise`, `formatTime`) stay green.
MD

# Prove the user-visible symptom is fixed.
bash /app/repro.sh > /tmp/oracle_repro.log 2>&1 || {
    echo "oracle: repro still fails (see /tmp/oracle_repro.log)" >&2
    tail -20 /tmp/oracle_repro.log >&2
    exit 1
}
grep -q "true false" /tmp/oracle_repro.log || {
    echo "oracle: repro did not print 'true false' (see /tmp/oracle_repro.log)" >&2
    tail -20 /tmp/oracle_repro.log >&2
    exit 1
}
echo "oracle: repro OK ('true false', exit 0)"

# Prove it with the project's own regression test (golden bytes from
# /opt/golden; compile against the REPAIRED tree sources, run under the
# published jest runner). Scratch only -- nothing is copied into /app/src.
RUN=$(mktemp -d /tmp/oracle-golden.XXXXXX)
trap 'rm -rf "$RUN"' EXIT
mkdir -p "$RUN/__tests__"
cp packages/jest-util/src/globsToMatcher.ts packages/jest-util/src/replacePathSepForGlob.ts "$RUN/"
cp /opt/tsapp/tsconfig.json /opt/tsapp/jest.config.json "$RUN/"
ln -s /opt/tsapp/node_modules "$RUN/node_modules"
cp /opt/golden/globsToMatcher.test.ts "$RUN/__tests__/"
if ! ( cd "$RUN" \
    && /opt/tsapp/node_modules/.bin/tsc -p tsconfig.json \
    && /opt/tsapp/node_modules/.bin/jest out/__tests__/ > /tmp/oracle_golden.log 2>&1 ); then
    echo "oracle: golden regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -qE "Tests:[ ]*10 passed" /tmp/oracle_golden.log || {
    echo "oracle: golden test did not actually run 10 passing cases" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
}
echo "oracle: golden regression test green (10/10)"

echo "oracle: fix applied, summary written, repro + golden regression green"
exit 0