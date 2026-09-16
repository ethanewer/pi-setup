#!/bin/bash
# Oracle for sheer-drift: applies the one-source-file fix to the real
# BurntSushi/ripgrep tree at /app/src (the CRLF-mode line-terminator trim in
# the printer must not index buf[end - 1] when end is 0: an empty matched
# line underflowed the index and panicked), rebuilds, writes /app/repro.sh
# and /app/summary.md, then proves the work: the reproduction must pass
# against the rebuilt fixed binary and must fail against the pristine
# pre-fix binary baked at /opt/prefix/rg; the printer crate's own unit tests
# and the regression module (with the upstream regression test planted from
# /opt/golden, then restored so the graded tree stays clean) must pass.
# Reads only /app, /solution and /opt.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the bounds-checked CRLF trim fix"

if ! cargo build --release --locked > /tmp/oracle_build.log 2>&1; then
    echo "oracle: cargo build failed after applying the fix; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi
test -x /app/src/target/release/rg || {
    echo "oracle: target/release/rg missing after build" >&2; exit 1
}

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the --crlf --color always empty-line crash.
# Contract: honour $RG_BIN (default /app/src/target/release/rg), set up the
# scenario in a fresh scratch dir under /tmp, print ripgrep's output only,
# exit 0 iff ripgrep exited 0 AND produced non-empty stdout.
set -u
RG_BIN=${RG_BIN:-/app/src/target/release/rg}
work=$(mktemp -d /tmp/rg-repro.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf '\n' > "$work/test.txt"
( cd "$work" && "$RG_BIN" 'x?' --crlf --color always test.txt ) > "$work/out" 2> "$work/err"
rc=$?
cat "$work/out"
cat "$work/err" >&2
[ "$rc" -eq 0 ] || exit 1
[ -s "$work/out" ] || exit 1
exit 0
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: searching a file containing an empty line with `--crlf --color always`
(using a pattern that matches an empty string, e.g. `x?`) panicked the
process and exited 101 without printing anything. Release builds reported
"index out of bounds: the len is 1 but the index is 18446744073709551615";
debug builds reported "attempt to subtract with overflow".

Cause: in the printer's CRLF-mode line-terminator trimming, after stripping
the line terminator the code looked one byte back to see whether it was a
carriage return, computing `buf[end - 1]`. For an empty matched line `end`
is 0, so the index arithmetic underflowed to 2^64 - 1 (len 1) or to 2^64 - 2
(len 14 in debug), and the buffer access panicked before the line could be
printed. The bad path is only reached when CRLF handling and color output
are enabled together.

Change: the look-behind is now bounds-checked - it only inspects bytes when
`end > 0` and uses a checked `get()` accessor, treating an out-of-range
index as "no CR to trim". Empty matched lines are printed like any other
line instead of crashing.

Verification: `/app/repro.sh` fails against the pre-fix binary at
/opt/prefix/rg (panic, exit 101, no output) and passes against the rebuilt
tree (exit 0, non-empty stdout); the printer crate's own unit tests pass;
the project's regression test module, including the upstream regression
test for this bug, passes.
MD
echo "oracle: wrote /app/summary.md"

# Prove the work in both directions with the project's own binary.
if ! bash /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the fixed tree; out:" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
if RG_BIN=/opt/prefix/rg bash /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix binary (expected failure)" >&2
    exit 1
fi
echo "oracle: repro OK on fixed tree, fails on pre-fix binary"

# Sanity: the project's own suites must stay green on the fixed tree.
if ! ( cd /app/src && cargo test --release -p grep-printer > /tmp/oracle_printer.log 2>&1 ); then
    echo "oracle: printer unit tests failed; tail:" >&2
    tail -20 /tmp/oracle_printer.log >&2
    exit 1
fi
grep -q "test result: ok\." /tmp/oracle_printer.log || {
    echo "oracle: printer unit tests did not pass" >&2
    exit 1
}

# Regression module with the upstream regression test planted, then restore
# the tree's copy of the file so the graded tree differs from the pinned
# commit in exactly the one source file.
RST="regression.rs"
RTD="tests"
cp /opt/golden/$RST /app/src/$RTD/$RST || {
    echo "oracle: cannot plant golden regression.rs" >&2; exit 1
}
if ! ( cd /app/src && cargo test --release --test integration -- regression \
        > /tmp/oracle_regression.log 2>&1 ); then
    echo "oracle: regression module failed; tail:" >&2
    tail -20 /tmp/oracle_regression.log >&2
    exit 1
fi
grep -q "^test regression::r1765 .* ok" /tmp/oracle_regression.log || {
    echo "oracle: upstream regression test r1765 did not pass" >&2
    exit 1
}
git -C /app/src checkout -- $RTD/$RST || {
    echo "oracle: could not restore $RTD/$RST" >&2; exit 1
}
dirty=$(git -C /app/src status --porcelain)
[ "$dirty" = " M crates/printer/src/standard.rs" ] || {
    echo "oracle: graded tree is not byte-identical to the pinned commit except standard.rs: $dirty" >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, tree rebuilds, repro OK both directions, printer + regression suites green, tree scope clean"
exit 0