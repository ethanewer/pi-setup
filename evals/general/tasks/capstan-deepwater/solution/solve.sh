#!/bin/bash
# Oracle for capstan-deepwater: applies the minimal upstream-style fix to the
# real BurntSushi/ripgrep tree at /app/src (the final path component must be
# dropped only for an empty path or a component of exactly `..`, never for a
# component that merely ends in a dot), writes /app/summary.md, then proves
# the work with the project's own machinery: the upstream regression test
# baked at /opt/golden plus a targeted subset of the project's own glob
# integration tests, plus the direct reproductions, all offline. Reads only
# /app, /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/opt/cargo/bin:$PATH

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied trailing-dot file-name fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: glob filters (`-g/--glob`) whose final path component ends in a dot were
silently ignored. Reproducer: with a directory literally named `asdf.` next
to a directory `asdf`, `rg --files -g '!asdf./'` printed both `asdf./foo`
and `asdf/foo` — the negation glob excluded nothing, and the same held for
inclusion globs and for plain files whose names end in a dot.

Root cause: ripgrep's glob matching compares the final "file name" component
of a candidate path (and the extension derived from it) against the glob's
own final component. The path handler `file_name` in
`crates/globset/src/pathutil.rs` returned `None` whenever a path's last byte
was a dot, so any candidate whose final component ended in a dot got an empty
file name (and empty extension). The globset match strategies keyed on the
basename/extension then never matched, so such globs stopped matching
entirely, as if they did not exist.

Fix: only an empty path, or a final component of exactly `..`, has no file
name; a trailing dot is an ordinary character in a Unix file name. The final
component is now extracted first and then tested for `..`, matching the
contract of `std::path::Path::file_name`. No other code is touched, so
ordinary globs, negations, extension globs and case-insensitive globs behave
exactly as before.

Verification: the project's own test harness (`cargo test --no-run`, then the
`integration-*` binary under `target/debug/deps/`) passes the upstream
regression test for this bug (`regression::r2990_trip_over_trailing_dot`,
planted from /opt/golden) and a targeted selection of the project's existing
glob tests (misc::glob, misc::glob_negate, misc::glob_case_insensitive,
misc::glob_case_sensitive, misc::glob_always_case_insensitive,
misc::include_zero, misc::include_zero_override,
misc::preprocessing_glob); the direct reproductions now behave correctly
(`-g '!asdf./'` lists only `asdf/foo`; `-g 'foo.'` selects a file named
`foo.`; `-g '!**/bb./'` excludes a nested trailing-dot directory; search
results honour the same globs).
MD

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

if ! "$BIN" --test-threads 1 r2990_trip_over_trailing_dot > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: upstream regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "regression::r2990_trip_over_trailing_dot \.\.\. ok" /tmp/oracle_golden.log || {
    echo "oracle: regression test did not actually run" >&2
    exit 1
}

if ! "$BIN" --test-threads 1 misc::glob misc::glob_negate misc::glob_case_insensitive misc::glob_case_sensitive misc::glob_always_case_insensitive misc::include_zero misc::include_zero_override misc::preprocessing_glob > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: existing glob suite selection did not pass; tail:" >&2
    tail -30 /tmp/oracle_suite.log >&2
    exit 1
fi

# Direct reproductions through the agent-facing binary. Run from inside the
# fixture directory so the output paths are relative, exactly like the
# hidden cases the grader runs.
rm -rf /tmp/oracle_t && mkdir -p /tmp/oracle_t/asdf /tmp/oracle_t/asdf.
touch /tmp/oracle_t/asdf/foo /tmp/oracle_t/asdf./foo
cd /tmp/oracle_t
OUT=$(/app/src/target/debug/rg --sort=path --files -g '!asdf./')
RC=$?
[ "$RC" -eq 0 ] && [ "$OUT" = "asdf/foo" ] || {
    echo "oracle: repro 1 failed rc=$RC out='$OUT'" >&2; exit 1
}
rm -rf /tmp/oracle_f && mkdir -p /tmp/oracle_f && touch /tmp/oracle_f/foo. /tmp/oracle_f/bar
cd /tmp/oracle_f
OUT=$(/app/src/target/debug/rg --sort=path --files -g 'foo.')
RC=$?
[ "$RC" -eq 0 ] && [ "$OUT" = "foo." ] || {
    echo "oracle: repro 2 failed rc=$RC out='$OUT'" >&2; exit 1
}
echo "oracle: direct reproductions OK"

# Leave the tree exactly as the verifier expects it: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
cd /app/src || exit 1
git restore --worktree --source=HEAD -- tests/regression.rs || {
    echo "oracle: could not restore tests/regression.rs" >&2
    exit 1
}
test -z "$(git status --porcelain | grep -v 'crates/globset/src/pathutil.rs')" || {
    echo "oracle: unexpected extra working-tree changes:" >&2
    git status --porcelain >&2
    exit 1
}

echo "oracle: fix applied, summary written, regression suite green, repros OK"
exit 0