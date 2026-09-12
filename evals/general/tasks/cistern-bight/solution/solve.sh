#!/bin/bash
# Oracle for cistern-bight: applies the one-clause fix to the real
# clap-rs/clap tree at /app/src (the long-help layout decision must ignore an
# argument whose possible-values list is hidden), writes /app/summary.md, then
# proves the work with the project's own builder test suite plus the upstream
# regression test (baked at /opt/golden), all offline. Reads only /app,
# /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/opt/cargo/bin:$PATH

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied help-layout fix patch"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: an argument whose possible-values list is hidden
(`hide_possible_values(true)`) could still force the long layout of
`-h`/`--help` output. The layout decision counted "the argument has possible
values that carry help texts" as a trigger without first checking whether the
value list is hidden, so an argument with a hidden-but-described value list
switched `--help` from the compact one-line listing to the long layout and
appended the `(see a summary with '-h')` hint, even though the hidden list
should not influence help output at all.

Fix: the possible-value-with-help trigger now only applies when the argument's
possible-values list is not hidden (`!is_hide_possible_values_set()`). Visible
arguments keep all previous layout behaviour (shown possible-value help and
long help still select the long layout).

Verification: the project's own builder test suite
(`cargo test --no-run -p clap`, then running every
`target/debug/deps/builder-*` binary end to end) passes fully with the
upstream regression test for this bug planted at
`tests/builder/help.rs`.
MD

# Prove the fix with the project's own machinery: plant the upstream
# regression test (golden bytes for tests/builder/help.rs from /opt/golden,
# already in the image), rebuild offline, and run the whole builder suite plus
# the regression test.
cp /opt/golden/help.rs tests/builder/help.rs
if ! cargo test --no-run -p clap > /tmp/oracle_build.log 2>&1; then
    echo "oracle: rebuild failed; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi
# Run the golden regression test explicitly (the exact test that failed
# before the fix), and the full builder suite.
BIN=$(ls -t target/debug/deps/builder-* | grep -v '\.d$' | head -1)
if ! "$BIN" --test hidden_possible_vals > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: upstream regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
if ! "$BIN" > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: full builder suite did not pass; tail:" >&2
    tail -30 /tmp/oracle_suite.log >&2
    exit 1
fi
grep -q "hidden_possible_vals \.\.\. ok" /tmp/oracle_golden.log || {
    echo "oracle: regression test did not actually run" >&2
    exit 1
}

# Leave the tree exactly as the verifier expects it: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
git restore --worktree --source=HEAD -- tests/builder/help.rs || {
    echo "oracle: could not restore tests/builder/help.rs" >&2
    exit 1
}

echo "oracle: fix applied, summary written, regression test and builder suite green"
exit 0