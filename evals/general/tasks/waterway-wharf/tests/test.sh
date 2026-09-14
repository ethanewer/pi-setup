#!/bin/bash
# Verifier for waterway-wharf (rust-lang/regex, upstream issue #1046).
#
# On the final /app tree the verifier:
#   1. requires the deliverables /app/repro.sh and /app/summary.md to exist
#      with content, /app/repro.sh executable;
#   2. asserts provenance: HEAD is the pinned parent commit, the upstream fix
#      commit is NOT reachable from the trial clone, no untracked scratch
#      files, and every tracked diff is confined to the two affected search
#      source files (regex-automata/src/meta/limited.rs and
#      regex-automata/src/meta/stopat.rs) and the data file
#      testdata/regression.toml; both source files must carry real changes;
#   3. checks the sha256 pins of the baked golden test and of the toolchain
#      (so a substituted compiler or golden cannot fake any later step);
#   4. PRE-FIX DIRECTION: reverts the two source files to the pinned blobs,
#      rebuilds, and runs the agent's own /app/repro.sh, which must FAIL with
#      the harness's truncated-match error (the reproduction is real);
#   5. POST-FIX DIRECTION: restores the agent's fix, rebuilds, and /app/repro.sh
#      must PASS;
#   6. plants the upstream regression test (baked at /opt/golden from the fix
#      commit via a throwaway clone) and requires the full integration harness
#      (all 64 existing tests: string, bytes, set, regression, misc, replace
#      and fuzz groups) to pass;
#   7. runs at least two authored hidden cases (tests/hidden/*/case.toml)
#      exercising the same code path from inputs the upstream test does not
#      use, each must pass.
#
# Reward is binary: 1 iff everything holds, else 0, written exactly as a
# single line.
set -u
mkdir -p /logs/verifier
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

PARENT_SHA=c5e9de9d6e07786eb1ff7f88d7871e0f0ef28c32
FIX_SHA=f15f3dcbc340eb98b40e60cc8b797263963d1e97
SRC=/app/src
GOLDEN=/opt/golden/regression.toml
export CARGO_NETWORK_OFFLINE=true

fail() {
    echo "VERIFY-FAIL: $*"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

# ---------- 1. deliverables ----------
[ -f /app/repro.sh ] || fail "deliverable /app/repro.sh missing"
[ -s /app/repro.sh ] || fail "deliverable /app/repro.sh empty"
[ -x /app/repro.sh ] || fail "deliverable /app/repro.sh not executable"
[ -f /app/summary.md ] && [ -s /app/summary.md ] || fail "deliverable /app/summary.md missing or empty"
echo "VERIFY-OK: /app/repro.sh and /app/summary.md present"

# ---------- 2. provenance and scope ----------
cd "$SRC" || fail "no /app/src"
HEAD=$(git rev-parse HEAD 2>/dev/null) || fail "not a git repository"
[ "$HEAD" = "$PARENT_SHA" ] || fail "HEAD is not the pinned parent commit ($HEAD)"
echo "VERIFY-OK: HEAD == pinned parent commit"
if git cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from the trial clone"
fi
echo "VERIFY-OK: upstream fix commit unreachable"
untracked=$(git status --porcelain | awk '$1 == "??" {print $2}')
[ -z "$untracked" ] || fail "untracked (non-ignored) files under /app/src: $untracked"
while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
        regex-automata/src/meta/limited.rs) ;;
        regex-automata/src/meta/stopat.rs) ;;
        testdata/regression.toml) ;;
        *) fail "modified beyond the allowed files: $f" ;;
    esac
done <<< "$(git diff --name-only HEAD)"
have_limited=$(git diff --name-only HEAD -- regex-automata/src/meta/limited.rs)
have_stopat=$(git diff --name-only HEAD -- regex-automata/src/meta/stopat.rs)
[ -n "$have_limited" ] || fail "no change in regex-automata/src/meta/limited.rs (one of the affected search files)"
[ -n "$have_stopat" ] || fail "no change in regex-automata/src/meta/stopat.rs (one of the affected search files)"
echo "VERIFY-OK: scope clean; both affected search files carry changes"

# ---------- 3. pins ----------
sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || fail "golden toml hash mismatch"
sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1 || fail "toolchain hash mismatch (substituted compiler?)"
echo "VERIFY-OK: golden + toolchain pins match"

# ---------- 4. pre-fix direction: revert, rebuild, repro must FAIL ----------
mkdir -p /tmp/save
cp regex-automata/src/meta/limited.rs /tmp/save/limited.rs
cp regex-automata/src/meta/stopat.rs /tmp/save/stopat.rs
git checkout -q HEAD -- regex-automata/src/meta/limited.rs regex-automata/src/meta/stopat.rs
touch regex-automata/src/meta/limited.rs regex-automata/src/meta/stopat.rs
sleep 1
if ( cd /app && bash /app/repro.sh > /tmp/prefix.out 2>&1 ); then
    fail "/app/repro.sh PASSED on the pre-fix tree (it must fail there: the bug must be real and the reproduction must target it)"
fi
grep -q "ww-repro-" /tmp/prefix.out \
    || fail "pre-fix repro output does not show its own harness entry name (ww-repro-*)"
grep -Eq "did not find expected matches|expected to find|FAILED" /tmp/prefix.out \
    || fail "pre-fix repro failure is not the harness asserting the case (truncated match)"
echo "VERIFY-OK: pre-fix direction - reproduction fails with the harness's truncated-match error"

# ---------- 5. post-fix direction: restore, rebuild, repro must PASS ----------
cp /tmp/save/limited.rs regex-automata/src/meta/limited.rs
cp /tmp/save/stopat.rs regex-automata/src/meta/stopat.rs
touch regex-automata/src/meta/limited.rs regex-automata/src/meta/stopat.rs
sleep 1
if ! ( cd /app && bash /app/repro.sh > /tmp/postfix.out 2>&1 ); then
    echo "VERIFY-FAIL: /app/repro.sh FAILED on the fixed tree; its output tail:"
    tail -40 /tmp/postfix.out
    fail "post-fix reproduction did not pass"
fi
grep -q "test result: ok" /tmp/postfix.out || fail "post-fix repro run did not report ok"
echo "VERIFY-OK: post-fix direction - reproduction passes on the fixed tree"

# ---------- 6. golden regression test + full existing harness ----------
cp "$GOLDEN" "$SRC/testdata/regression.toml"
touch "$SRC/testdata/regression.toml"
sleep 1
if ! ( cd "$SRC" && REGEX_TEST=non-prefix-literal-quit-state cargo test --test integration -j1 > /tmp/golden.out 2>&1 ); then
    echo "VERIFY-FAIL: planted upstream regression test failed; tail:"
    tail -30 /tmp/golden.out
    fail "upstream golden regression test did not pass"
fi
grep -q "test result: ok" /tmp/golden.out || fail "golden run did not report ok"
echo "VERIFY-OK: upstream golden regression test passes"
touch "$SRC/testdata/regression.toml"
sleep 1
if ! ( cd "$SRC" && cargo test --test integration -j1 > /tmp/full.out 2>&1 ); then
    echo "VERIFY-FAIL: full existing integration harness failed; tail:"
    tail -40 /tmp/full.out
    fail "project's own full integration harness did not pass"
fi
grep -q "test result: ok" /tmp/full.out || fail "full suite did not report ok"
echo "VERIFY-OK: full existing integration harness green (with the planted golden entry)"

# ---------- 7. hidden cases (>= 2 required, each on a fresh golden base) ----------
count=0
for h in /tests/hidden/*/case.toml; do
    [ -f "$h" ] || continue
    count=$((count + 1))
    cp "$GOLDEN" "$SRC/testdata/regression.toml"
    cat "$h" >> "$SRC/testdata/regression.toml"
    name=$(grep -m1 'name = ' "$h" | sed -E 's/.*name = "([^"]+)".*/\1/')
    [ -n "$name" ] || fail "hidden case $h has no name"
    touch "$SRC/testdata/regression.toml"
    sleep 1
    if ! ( cd "$SRC" && REGEX_TEST="$name" cargo test --test integration -j1 > /tmp/hidden.out 2>&1 ); then
        echo "VERIFY-FAIL: hidden case $name failed; tail:"
        tail -30 /tmp/hidden.out
        fail "hidden case $name did not pass"
    fi
    grep -q "test result: ok" /tmp/hidden.out || fail "hidden case $name did not report ok"
    echo "VERIFY-OK: hidden case $name passes"
done
[ "$count" -ge 2 ] || fail "fewer than two hidden cases were run (count=$count)"

echo "VERIFY-OK: all checks passed"
echo 1 > /logs/verifier/reward.txt
exit 0