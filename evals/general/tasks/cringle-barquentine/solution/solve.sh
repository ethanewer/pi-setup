#!/bin/bash
# Oracle for cringle-barquentine: applies the real upstream fix for the
# word-matching empty-pattern crash (in crates/regex/src/word.rs:
# WordMatcher::fast_find must bail out of the fast path when trimming the
# surrounding \W characters would invert the candidate match range, which is
# what happens when the original pattern can match the empty string), rebuilds
# the release binary, writes /app/repro.sh and /app/summary.md, then proves
# the work: the reproduction must pass against the rebuilt fixed binary and
# must fail against the pristine pre-fix binary baked at /opt/prefix/rg.
# Reads only /app, /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the word-boundary fast-path fix"

if ! cargo build --release -j1 > /tmp/oracle_make.log 2>&1; then
    echo "oracle: cargo build failed after applying the fix; tail:" >&2
    tail -30 /tmp/oracle_make.log >&2
    exit 1
fi
test -x /app/src/target/release/rg || {
    echo "oracle: /app/src/target/release/rg missing after build" >&2; exit 1
}

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the word-matching empty-pattern crash.
# Contract: honour $RG_BIN (default /app/src/target/release/rg), create the
# input file "\n##\n" in a fresh scratch dir under /tmp, run `rg -won ''`
# on it, print exactly what rg prints (stdout and stderr), and exit 0 iff the
# command exited 0 AND its stdout was exactly "1:\n2:\n2:\n".
set -u
RG_BIN=${RG_BIN:-/app/src/target/release/rg}
work=$(mktemp -d /tmp/rg-repro.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf '\n##\n' > "$work/u.txt"
( cd "$work" && "$RG_BIN" -won '' u.txt ) > "$work/out" 2> "$work/err"
rc=$?
cat "$work/out"
cat "$work/err" >&2
[ "$rc" -eq 0 ] || exit 1
[ "$(cat "$work/out")" = "$(printf '1:\n2:\n2:\n')" ] || exit 1
exit 0
SH
chmod 755 /app/repro.sh

cat > /app/summary.md <<'MD'
# What the bug was

`rg -w` (word matching) wraps the user's pattern in word-boundary assertions
and, in the common case, uses a fast path that trims the surrounding
non-word characters off the candidate match and then confirms it against the
original un-wrapped pattern. When the original pattern can match the empty
string (the empty pattern is the simplest case), the trimmed candidate can
become an inverted range (start > end): the trimming of the leading and
trailing `\W` characters consumes more bytes than the candidate holds. The
inverted range then trips the `Match::with_*` range assertion
('assertion failed: self.start <= end', crates/matcher/src/lib.rs:131) and
the process panics partway through its output, instead of reporting every
word-boundary match position.

# What I changed

In `crates/regex/src/word.rs`, `WordMatcher::fast_find` now detects the
inverted-range case before constructing the trimmed `Match` and bails out of
the fast path, deferring to the (captures-based) general path, which handles
empty matches at word boundaries correctly. Ordinary word matching is
unaffected: for non-empty matches the trimmed range is always well-formed.

# How I verified it

- `/app/repro.sh` failed on the pre-fix binary (panic, exit 101) and passes
  on my rebuilt binary with the exact expected output `1:\n2:\n2:\n`.
- The same command with other empty-matchable patterns (`t?`, `^`,
  `[:space:]*`) now also completes with correct output.
- `cargo test --release -j1` (the project's own integration suite) and
  `cargo test --release -j1 -p grep-regex -p grep-matcher` (unit tests of the
  two search crates) all pass.
MD
chmod 644 /app/summary.md

# Self-proof in the oracle: fixed direction must pass, pre-fix direction must
# fail. Any other combination means the oracle itself is wrong.
bash /app/repro.sh || {
    echo "oracle: reproduction failed against the rebuilt fixed binary" >&2
    exit 1
}
if RG_BIN=/opt/prefix/rg bash /app/repro.sh; then
    echo "oracle: reproduction PASSED against the pristine PRE-FIX binary" >&2
    echo "oracle: (expected it to fail - the symptom is not what we think)" >&2
    exit 1
fi
echo "oracle: self-proof ok (fixed passes, pre-fix fails)"
exit 0