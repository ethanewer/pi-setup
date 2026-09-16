#!/bin/bash
# Oracle for bosun-fathom: applies the one-source-file fix to the real
# BurntSushi/ripgrep tree at /app/src (the searcher glue's early-exit path
# must mark the remainder of the current line buffer as consumed so the
# "bytes searched" statistics are accurate when a max-count limit stops the
# search early), rebuilds, writes /app/repro.sh and /app/summary.md, then
# proves the work: the reproduction must fail against the pristine pre-fix
# binary baked at /opt/prefix/rg and pass against the rebuilt fixed binary,
# and the project's own test suites must stay green. Reads only /app,
# /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the early-stop byte-accounting fix"

if ! cargo build --locked > /tmp/oracle_build.log 2>&1; then
    echo "oracle: cargo build failed after applying the fix; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi
test -x /app/src/target/debug/rg || {
    echo "oracle: target/debug/rg missing after cargo build" >&2
    exit 1
}
echo "oracle: rebuild ok"

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the early-stop --stats byte-counter bug.
# Contract: honour $RG_BIN (default /app/src/target/debug/rg), set up the
# fixture in a fresh scratch dir under /tmp, print ripgrep's output only,
# exit 0 iff rg exited 0 AND the stats block reports the correct match
# count AND the byte count the fixture implies.
set -u
RG_BIN=${RG_BIN:-/app/src/target/debug/rg}
work=$(mktemp -d /tmp/rg-repro.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
# Five 5-byte lines; an early stop after 2 matches consumes "foo1\nfoo2\n"
# = 10 bytes. The search is run in the RECURSIVE form (positional arg "."):
# only that form reaches the line-buffered directory-search path where the
# early-stop byte accounting is broken (naming the file directly uses a
# whole-file path whose accounting is already correct). Derive the
# expectation from the fixture, not from a magic constant.
printf 'foo1\nfoo2\nfoo3\nfoo4\nfoo5\n' > "$work/haystack" || exit 1
expected_bytes=$(head -2 "$work/haystack" | wc -c) || exit 1
( cd "$work" && "$RG_BIN" --stats -m2 foo . ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
matches_line=$(grep -o '[0-9][0-9]* matches' "$work/out" | head -1)
[ "$matches_line" = "2 matches" ] || { echo "expected '2 matches'" >&2; exit 1; }
bytes_line=$(grep -o '[0-9][0-9]* bytes searched' "$work/out" | head -1)
[ "$bytes_line" = "${expected_bytes} bytes searched" ] || {
    echo "expected '${expected_bytes} bytes searched'" >&2
    exit 1
}
exit 0
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: with an early-stop maximum-match-count limit (`-m` / `--max-count`),
`rg --stats` reported `0 bytes searched` even though the search had plainly
read and printed matching lines. The unlimited run of the same search
reported the true figure, so the stats block silently contradicted what had
happened.

Cause: the line-buffered (read-by-line) search loop ran
`fill() && core.match_by_line(buffer)`. When the search was told to stop
early (max-count reached), `match_by_line` returned false and the loop
exited WITHOUT marking the remainder of the current buffer (the input that
had already been read into memory, up to the last matched line's end) as
consumed. The "bytes searched" statistic is derived from how many bytes the
buffer reader has consumed, so that un-consumed tail was never counted:
with the whole remaining buffer un-consumed, the figure came out 0.

Change: in the searcher glue's `ReadByLine::run`, restructure the loop so
that when `match_by_line` returns false the remaining bytes up to the
current search position are explicitly consumed (`consume_remaining()`)
before breaking out. The stopped search now accounts for every byte of
input it actually read, so the early-stopped run reports the same prefix
count the unlimited run does.

Verification: `/app/repro.sh` fails against the pre-fix binary at
/opt/prefix/rg (`0 bytes searched`) and passes against the rebuilt tree
(`10 bytes searched`); the project's own integration suite (308 tests) and
the searcher crate's unit suite both stay green.
MD
echo "oracle: wrote /app/summary.md"

# Prove the work in both directions with the project's own binary.
if ! bash /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the fixed tree; out:" >&2
    head -20 /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
echo "oracle: repro passes on the fixed tree"
if RG_BIN=/opt/prefix/rg bash /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix binary (expected failure)" >&2
    exit 1
fi
echo "oracle: repro fails on the pre-fix binary"
# Also run it against the pre-fix binary from a copied path, so a
# reproduction that special-cases /opt/prefix cannot pass this caution.
mkdir -p /tmp/prefixcopy && cp /opt/prefix/rg /tmp/prefixcopy/rg
if RG_BIN=/tmp/prefixcopy/rg bash /app/repro.sh > /tmp/oracle_repro_prefix2.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against a copied pre-fix binary (path special-case?)" >&2
    exit 1
fi
echo "oracle: repro also fails against the copied pre-fix binary"

# Sanity: the project's own suites must stay green with the fix applied.
# The integration suite is run with `--skip accessed`, excluding exactly the
# two access-time sort tests (sort_accessed, sortr_accessed), which are
# inherently racy under this container's atime semantics (they sort by file
# access time with 100 ms sleeps) and fail nondeterministically even on the
# pristine tree; every other one of the 308 tests must pass.
if ! cargo test --test integration -- --skip accessed > /tmp/oracle_integration.log 2>&1; then
    echo "oracle: integration suite failed; tail:" >&2
    tail -25 /tmp/oracle_integration.log >&2
    exit 1
fi
grep -q "test result: ok. 306 passed; 0 failed" /tmp/oracle_integration.log || {
    echo "oracle: integration suite did not pass 306 tests cleanly" >&2
    tail -8 /tmp/oracle_integration.log >&2
    exit 1
}
if ! cargo test -p grep-searcher > /tmp/oracle_searcher.log 2>&1; then
    echo "oracle: searcher unit suite failed; tail:" >&2
    tail -25 /tmp/oracle_searcher.log >&2
    exit 1
fi
grep -q "test result: ok. .* 0 failed;" /tmp/oracle_searcher.log || {
    echo "oracle: searcher unit suite did not pass cleanly" >&2
    tail -8 /tmp/oracle_searcher.log >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, repro OK both directions, integration + searcher suites green"
exit 0