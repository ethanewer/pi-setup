#!/bin/bash
# Oracle for cutwater-swell: applies the real upstream fix (the whole
# crates/regex/src/literal.rs change of upstream commit 9d738ad, including
# the updated extraction unit-test expectations and the new regression test),
# rebuilds with cargo, writes /app/repro.sh and /app/summary.md, then proves
# the work: the reproduction must pass against the rebuilt tree and must fail
# against the pristine pre-fix binary baked at /opt/prefix/rg, and the
# project's own grep-regex unit suite must stay green. Reads only /app,
# /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

export PATH=/opt/rust/bin:$PATH CARGO_NET_OFFLINE=true

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to the clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the inner-literal-extraction fix (crates/regex/src/literal.rs)"

if ! cargo build > /tmp/oracle_build.log 2>&1; then
    echo "oracle: cargo build failed after applying the fix; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi
test -x /app/src/target/debug/rg || { echo "oracle: target/debug/rg missing" >&2; exit 1; }
echo "oracle: rebuilt target/debug/rg"

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the case-insensitive-alternation false negative.
# Contract: honour $RG_BIN (default /app/src/target/debug/rg), build a
# scratch input under /tmp, run one search with a triggering pattern, print
# only rg's output, exit 0 iff every expected matching line is present.
set -u
RG_BIN=${RG_BIN:-/app/src/target/debug/rg}
work=$(mktemp -d /tmp/rg-repro.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf 'e-x\ne-X\nplain\nex\n' > "$work/f"
out=$("$RG_BIN" '(?i:e.x|ex)' "$work/f" 2>&1)
rc=$?
printf '%s\n' "$out"
[ "$rc" -eq 0 ] || exit 1
for want in 'e-x' 'e-X' 'ex'; do
    printf '%s\n' "$out" | grep -Fqx "$want" || exit 1
done
exit 0
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: patterns combining the case-insensitive flag with an alternation whose
branches contain a wildcard silently missed matches. `rg '(?i:e.x|ex)'` on a
file containing `e-x` printed nothing and exited 1 even though the pattern
unambiguously matches `e-x`; on a file containing both lines only the `ex`
line was printed, with exit status 0, so the missed matches were invisible.

Cause: ripgrep derives a set of "must-appear" literal strings from a pattern
to accelerate searching. For `(?i:e.x|ex)`, inner-literal extraction from
the two alternation branches were combined into the over-specific set
{EX, Ex, eX, ex} and treated as a required prefix of any candidate match
position. No string `e-x` matches any element of that set (it contains no
two-character substring of them), so every valid match was rejected before
the regex engine ran. The defect only fires when the extracted set stays
exact; for many similar patterns extraction degrades to inexact on its own,
which is why only some spellings reproduced it.

Change: in crates/regex/src/literal.rs, the sequence-union step now keeps
the "prefix" attribute only if BOTH operands are prefix-exact, and the
sequence-choice step (`choose`) now always returns an inexact sequence
(because by choosing one candidate extraction, the other is discarded). The
extracted set for `(?i:e.x|ex)` therefore degrades to the permissive
inexact set {X, x} (a substring which every matching line does contain),
while exact extraction is preserved for patterns where it is provably safe.
Four existing unit-test expectations that encoded the old (overly exact)
extraction behaviour were updated to the corrected behaviour, and the
project's own regression test for this bug was added
(`case_insensitive_alternation`, asserting the extraction is {I(X), I(x)}).

Verification: /app/repro.sh fails against the pristine pre-fix binary at
/opt/prefix/rg (the `e-x` and `e-X` lines are missing from the output) and
passes against the rebuilt tree (all expected lines present); a full
`cargo build` succeeds; `cargo test -p grep-regex --lib` passes all 25
tests including the new regression test; additional CLI checks with other
alphabets (`(?i:k.k|kk)`, `(?i:t.t|tt)`), a two-character gap
(`(?i:e..x|ex)`), mixed casing and mid-line occurrences, and `rg -c`
line counting all now return the correct matches.
MD
echo "oracle: wrote /app/summary.md"

# Prove the work in both directions with the project's own binary. The
# pre-fix binary must first prove it is genuinely executable and does
# ordinary searches, so the "must fail" direction is not vacuous.
test -x /opt/prefix/rg || { echo "oracle: /opt/prefix/rg is not executable" >&2; exit 1; }
printf 'box\n' | /opt/prefix/rg -c box - > /tmp/oracle_smoke.out 2>&1
rc=$?
if [ "$rc" -ne 0 ] || [ "$(cat /tmp/oracle_smoke.out)" != "1" ]; then
    echo "oracle: pre-fix binary failed ordinary-search smoke test" >&2
    exit 1
fi
if ! bash /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the fixed tree; out:" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
if RG_BIN=/opt/prefix/rg bash /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix binary (expected failure)" >&2
    cat /tmp/oracle_repro_prefix.out >&2
    exit 1
fi
echo "oracle: repro OK on fixed tree, fails on pre-fix binary"

# Sanity: the project's own unit suite must stay green on the fixed tree.
if ! cargo test -p grep-regex --lib > /tmp/oracle_test.log 2>&1; then
    echo "oracle: cargo test -p grep-regex --lib failed; tail:" >&2
    tail -30 /tmp/oracle_test.log >&2
    exit 1
fi
grep -q "25 passed" /tmp/oracle_test.log || {
    echo "oracle: grep-regex lib suite did not pass all 25 tests" >&2
    tail -20 /tmp/oracle_test.log >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, tree rebuilds, repro OK both directions, 25 unit tests green"
exit 0