#!/bin/bash
# Oracle for alewife-anchorage: applies the one-source-file fix to the real
# BurntSushi/ripgrep tree at /app/src (the ancestor-ignore walker must not
# strip the leading '.' off relative paths when the parent ignore's directory
# is '.' - doing so mangles hidden file names and makes whitelisted hidden
# files vanish for the '.' search-path spelling), writes /app/repro.sh and
# /app/summary.md, then proves the work with the project's own test harness
# (the upstream regression test baked at /opt/golden plus a targeted subset
# of the project's own ignore/whitelist integration tests), all offline.
# Reads only /app, /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/opt/cargo/bin:$PATH

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied ancestor-ignore '.'-path fix"

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the whitelisted-hidden-file bug.
# Contract: honour $RG_BIN (default /app/src/target/debug/rg), set up the
# scenario in a fresh scratch dir under /tmp, print ripgrep's output only,
# exit 0 iff the whitelisted hidden file appears in the output.
unset RIPGREP_CONFIG_PATH
RG_BIN=${RG_BIN:-/app/src/target/debug/rg}
work=$(mktemp -d /tmp/rg-repro.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/subdir"
printf 'some text\n' > "$work/subdir/.foo.txt"
printf '!.foo.txt\n' > "$work/.ignore"
( cd "$work/subdir" && "$RG_BIN" --no-config --files . ) > "$work/out.txt" 2>&1
rc=$?
cat "$work/out.txt"
[ $rc -eq 0 ] && grep -q '\.foo\.txt' "$work/out.txt" && exit 0
exit 1
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: when ripgrep's file listing is started inside a subdirectory and the
search path is given as `.`, files that are hidden (leading dot) and
explicitly whitelisted back in with a negated rule (for example `!.foo.txt`
in an ignore file) are silently skipped - `rg --files .` prints nothing and
exits 1 even though the whitelisted hidden file should be listed. Every
other path spelling (no path, or `./`) from the same directory, and every
spelling from the parent directory, works correctly.

Cause: the ancestor-ignore walker in `crates/ignore/src/dir.rs` rewrites a
candidate path relative to the last non-absolute parent ignore before it
joins the path onto the absolute base for matching. When the search path is
`.`, the parent ignore's directory is also `.`; the old code then stripped a
leading `./`/`.`/`/` prefix off the relative path, so a hidden name like
`.foo.txt` (already prefixed with `./` by the walker) lost its leading dot
after the join, the whitelist rule no longer matched it, and the default
skip-hidden rule filtered the file out. Searching without a path argument
(or with `./`) never produced the mangling, which is why only the `.`
spelling was affected.

Fix: in the ancestor-ignore walker, when the parent ignore's directory is
exactly `.`, return the path unchanged (no prefix stripping) - the join with
the absolute base still produces the correct absolute path, and hidden names
such as `.foo.txt` are preserved so the whitelist rule matches. All other
cases keep exactly the previous behaviour.

Verification: `/app/repro.sh` fails (exit 1, no listing) against the
pre-fix binary at /opt/prefix/rg and passes (exit 0, `./.foo.txt` listed)
against the built tree; the project's own test harness, with the upstream
regression test for this bug planted from /opt/golden
(`r3173_hidden_whitelist_only_dot`), passes that test and a targeted
selection of existing ignore/whitelist integration tests; direct `rg
--files .` reproductions with other hidden names, other whitelist patterns,
deeper nesting and hidden directories all list the expected files.
MD
echo "oracle: wrote /app/summary.md"

# Prove the fix with the project's own machinery: plant the upstream
# regression test (golden bytes from /opt/golden, already in the image),
# rebuild offline, and run the targeted harness subset.
cp /opt/golden/regression.rs tests/regression.rs
if ! cargo test --no-run > /tmp/oracle_build.log 2>&1; then
    echo "oracle: rebuild failed; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi
BIN=""
for b in $(ls -t target/debug/deps/integration-* 2>/dev/null); do
    case "$b" in *.d) continue ;; esac
    BIN=$b; break
done
[ -n "$BIN" ] && [ -x "$BIN" ] || { echo "oracle: integration binary not found" >&2; exit 1; }

if ! "$BIN" r3173_hidden_whitelist_only_dot > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: upstream regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "regression::r3173_hidden_whitelist_only_dot ... ok" /tmp/oracle_golden.log || {
    echo "oracle: regression test did not actually run" >&2
    exit 1
}

if ! "$BIN" r2711 r829_original r829_2731 r829_2747 r829_2778 r807 \
      f68_no_ignore_vcs f1138_no_ignore_dot f1207_ignore_encoding \
      f1404_nothing_searched_ignored f1420_no_ignore_exclude f1466_no_ignore_files \
      > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: existing ignore/whitelist suite selection did not pass; tail:" >&2
    tail -30 /tmp/oracle_suite.log >&2
    exit 1
fi

# Direct reproduction through the deliverable, both directions.
if ! /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the fixed tree; out:" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
if RG_BIN=/opt/prefix/rg /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix binary (expected failure)" >&2
    exit 1
fi
echo "oracle: repro OK on fixed tree, fails on pre-fix binary"

# Leave the tree exactly as the verifier expects it: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
git restore --worktree --source=HEAD -- tests/regression.rs || {
    echo "oracle: could not restore tests/regression.rs" >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, regression suite green, repro OK"
exit 0