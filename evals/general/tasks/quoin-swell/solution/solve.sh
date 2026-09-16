#!/bin/bash
# Oracle for quoin-swell: applies the one-source-file fix to the real
# sharkdp/fd tree at /app/src (Opts.normalize_path must rewrite a search-path
# argument of "-" to "./-" so the underlying walker treats it as a literal
# path instead of silently matching nothing - see sharkdp/fd#849), rebuilds,
# writes /app/repro.sh and /app/summary.md, then proves the work: the
# reproduction must pass against the rebuilt fixed binary and must fail
# against the pristine pre-fix binary baked at /opt/prefix/fd, and the
# project's own test suite (minus the known 1-CPU-bound test_exec_nulls) must
# stay green. Reads only /app, /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/opt/cargo/bin:$PATH CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup CARGO_NET_OFFLINE=true

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the '-' search-path fix"

if ! cargo build -j1 > /tmp/oracle_build.log 2>&1; then
    echo "oracle: cargo build failed after applying the fix; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi
test -x /app/src/target/debug/fd || { echo "oracle: fd binary missing after build" >&2; exit 1; }

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the silent-empty '-' search path.
# Contract: honour $FD_BIN (default /app/src/target/debug/fd), set up the
# scenario in a fresh scratch dir under /tmp, cd into it, run the affected
# command exactly (`fd . -`), print fd's output only, exit 0 iff the command
# exits 0 AND the captured output contains ./-/foo.txt.
set -u
FD_BIN=${FD_BIN:-/app/src/target/debug/fd}
work=$(mktemp -d /tmp/fd-dash.XXXXXX) || { echo "cannot create scratch dir" >&2; exit 1; }
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/-" || exit 1
echo "needle" > "$work/-/foo.txt" || exit 1
( cd "$work" && "$FD_BIN" . - ) > "$work/out" 2>&1
rc=$?
cat "$work/out"
[ "$rc" -eq 0 ] || exit 1
grep -qxF "./-/foo.txt" "$work/out" || exit 1
exit 0
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: pointing a search at a directory whose name is literally a single dash
(`fd . -`, run from a directory that really contains a subdirectory named
`-`) silently returns NO results while exiting 0 - the directory exists on
disk and `fd . ./-` finds the very same files, so the outcome depends only on
how the search-path argument is spelled. A wrapper script or variable that
hands `-` to the tool quietly searches nothing.

Cause: the search-path handling only rewrote the special root `.` (to `./`,
as a walker workaround) and left a bare `-` argument unchanged, so the
underlying walker received `-` and silently treated it as nothing to walk.

Change: in the search-path normalisation, a path argument exactly equal to
`-` is now rewritten to `./-` (joined onto `.`), so the walker treats it as
the literal path it names. Smallest possible change: one extra branch in the
same function, exactly mirroring the existing `.` special case.

Verification: /app/repro.sh fails against the pre-fix binary at
/opt/prefix/fd (empty output, exit 1) and passes against the rebuilt tree
(prints `./-/foo.txt`, exit 0); the project's own suite passes with
`cargo test -j1 -- --skip test_exec_nulls` (test_exec_nulls is a known
1-CPU-sandbox artifact unrelated to this change; it fails on the pristine
parent tree too); `fd . -` now also finds files under nested dash-named
directories, with filtered patterns, alongside other search paths, and via
the long option form.
MD
echo "oracle: wrote /app/summary.md"

# Prove the work in both directions with the project's own binary.
if ! bash /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the fixed tree; out:" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
if FD_BIN=/opt/prefix/fd bash /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix binary (expected failure)" >&2
    exit 1
fi
echo "oracle: repro OK on fixed tree, fails on pre-fix binary"

# Sanity: the project's own suite must stay green on the fixed tree (minus
# the known 1-CPU-bound test_exec_nulls).
if ! cargo test -j1 -- --skip test_exec_nulls > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: cargo test failed; tail:" >&2
    tail -30 /tmp/oracle_suite.log >&2
    exit 1
fi
grep -q "test result: ok. 139 passed; 0 failed" /tmp/oracle_suite.log || {
    echo "oracle: unit tests not all green" >&2
    exit 1
}
grep -q "test result: ok. 107 passed; 0 failed" /tmp/oracle_suite.log || {
    echo "oracle: integration suite not all green (expected 107 passed, 1 filtered)" >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, tree rebuilds, repro OK both directions, suite green"
exit 0