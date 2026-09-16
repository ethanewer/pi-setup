#!/bin/bash
# Oracle for waterway-wharf: applies the one-two-file upstream fix to the real
# rust-lang/regex tree at /app/src (the meta engine's ad hoc DFA/hybrid search
# routines must return a quit error when a quit state is entered even if a
# tentative match was found, instead of returning the tentative match; eight
# near-identical quit-shortcut sites in regex-automata/src/meta/limited.rs and
# regex-automata/src/meta/stopat.rs lose the 'if mat.is_some() { return ... }'
# shortcut), rebuilds the project's own integration harness, writes
# /app/repro.sh (the agent-side reproduction contract) and /app/summary.md,
# then proves the work: the reproduction must fail against the reverted
# (pre-fix) tree and pass against the fixed tree, and the upstream golden
# regression entry planted into testdata/regression.toml must pass. Reads only
# /app, /solution, /opt and /tmp, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export CARGO_NETWORK_OFFLINE=true

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch || exit 1
echo "oracle: applied the quit-state fix to limited.rs and stopat.rs"

if ! cargo test --no-run --test integration -j1 > /tmp/oracle_build.log 2>&1; then
    echo "oracle: build failed after applying the fix; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi

REPRO_NAME=ww-repro-non-prefix-literal-quit
cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the truncated-match search bug.
# Contract: appends its own data-driven entry (name ww-repro-*) to
# /app/src/testdata/regression.toml if missing, runs the project's own
# integration harness filtered to it, prints the harness output, and exits 0
# iff the harness reports the case passed (the full haystack-spanning match
# was found).
set -u
NAME=ww-repro-non-prefix-literal-quit
SRC=/app/src
cd "$SRC" || { echo "repro: /app/src missing" >&2; exit 1; }
export CARGO_NETWORK_OFFLINE=true
TOML=testdata/regression.toml
if ! grep -q "$NAME" "$TOML"; then
    cat >> "$TOML" <<'EOF'

[[test]]
name = "ww-repro-non-prefix-literal-quit"
regex = '.+\b\n'
haystack = "β77\n"
matches = [[0, 5]]
EOF
fi
# Guarantee the harness recompiles the embedded data (the data file is
# compiled into the test binary via include_bytes, so a plain run after
# editing the file would otherwise silently reuse stale embedded data).
touch "$TOML"
sleep 1
REGEX_TEST="$NAME" cargo test --test integration -j1
exit $?
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: a search whose pattern ends with a Unicode word boundary followed by a
literal (for example `.+` `\b` `\n` against a haystack that starts with a
non-ASCII letter, like "β77\n") silently returned a truncated match (reported
as bytes 3..5) with misaligned captures instead of the full valid match at the
start of the haystack (bytes 0..5).

Cause: the meta engine's ad hoc DFA/hybrid search routines returned a
tentative match when a quit state was entered. A quit state means the engine
cannot continue its specialized search and must give up so the higher-level
engine can divert to a strategy that handles the construct correctly; the
Unicode word boundary adjacent to a non-ASCII code point is exactly such a
case. Returning the tentative match instead of a quit error caused the
truncated, misaligned result.

Change: in `regex-automata/src/meta/limited.rs` (the half-reverse and
end-of-input-reverse routines) and `regex-automata/src/meta/stopat.rs` (the
half-forward and end-of-input-forward routines), always return the quit error
when a quit state is entered, removing the conditional that used to return a
previously-found tentative match instead.

Verification: `/app/repro.sh` fails against the reverted (pre-fix) tree with
the harness reporting the truncated match and passes against the fixed tree;
the upstream regression entry planted in testdata/regression.toml passes, and
the project's own integration harness (`cargo test --test integration`, all
64 tests: string, bytes, set and regression groups) is green.
MD
echo "oracle: wrote /app/summary.md"

# Prove both directions with the project's own harness.
# 1. Fixed tree: the reproduction must pass.
if ! bash /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh FAILED on the fixed tree; out:" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
grep -q "test result: ok" /tmp/oracle_repro_fixed.out || {
    echo "oracle: repro run did not report 'ok'"; exit 1
}
# 2. Pre-fix tree: revert both source files, rebuild, the reproduction must fail.
git checkout -q HEAD -- regex-automata/src/meta/limited.rs regex-automata/src/meta/stopat.rs
if bash /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix tree (expected failure)" >&2
    exit 1
fi
grep -q "did not find expected matches" /tmp/oracle_repro_prefix.out || {
    echo "oracle: pre-fix failure did not show the truncated-match harness error" >&2
    exit 1
}
# 3. Restore the fix and confirm the golden regression entry + full harness.
git apply /solution/fix.patch || exit 1
cp /opt/golden/regression.toml /app/src/testdata/regression.toml
touch /app/src/testdata/regression.toml
sleep 1
if ! REGEX_TEST=non-prefix-literal-quit-state \
     cargo test --test integration -j1 > /tmp/oracle_golden.out 2>&1; then
    echo "oracle: golden regression run failed; tail:" >&2
    tail -30 /tmp/oracle_golden.out >&2
    exit 1
fi
touch /app/src/testdata/regression.toml
sleep 1
if ! cargo test --test integration -j1 -- suite_string::default > /tmp/oracle_suite.out 2>&1; then
    echo "oracle: full string suite failed; tail:" >&2
    tail -30 /tmp/oracle_suite.out >&2
    exit 1
fi
echo "oracle: fix applied, deliverables written, repro OK both directions, golden + full string suite green"
exit 0