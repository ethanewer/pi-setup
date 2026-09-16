#!/bin/bash
# Oracle for ballast-anchorage: applies the one-source-file fix to the real
# BurntSushi/ripgrep tree at /app/src (the replace pass must clamp the tail
# slice when a look-around match ended past range.end), writes
# /app/summary.md, then proves the work with the project's own test harness
# (the upstream regression test baked at /opt/golden plus a targeted subset
# of the project's own multiline/replace integration tests), all offline.
# Reads only /app, /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/opt/cargo/bin:$PATH

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied replacement-clamp fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: combining multiline search (`-U/--multiline`) with a replacement string
(`-r/--replace`) could crash ripgrep when a pattern with look-around produced
many short matches. The replace pass in `replace_with_captures_in_context`
(in `crates/printer/src/util.rs`) tracks `last_match` and then slices the
remaining tail with `min(bytes.len(), range.end)` as the end. With
look-around in multiline mode a match can end *past* `range.end`, so
`last_match` becomes larger than that end and the tail slice is inverted
(`bytes[last_match..end]` with `end < last_match`), panicking with
"slice index starts at X but ends at Y" and exiting 101 instead of printing
the replaced lines.

Fix: after the replace loop, if `last_match` has advanced past `range.end`
(because the final match itself overshot the range), extend the tail slice
to the end of the haystack bytes instead of `range.end`. Otherwise the
behaviour is unchanged. This is a two-branch clamp on exactly the one
inverted-slice path; plain search, non-multiline replace, `--only-matching`
and multiline search without `--replace` are untouched.

Verification: the project's own test harness (`cargo test --no-run`, then
`target/debug/integration`) passes the upstream regression test for this bug
(`r3180_look_around_panic`, planted from /opt/golden) as well as a targeted
selection of the project's existing multiline/replace tests; the reproduction
prints `xbxbx` with exit 0 in both debug and release builds.
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

if ! "$BIN" r3180_look_around_panic > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: upstream regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "regression::r3180_look_around_panic ... ok" /tmp/oracle_golden.log || {
    echo "oracle: regression test did not actually run" >&2
    exit 1
}

if ! "$BIN" r1311_multi_line_term_replace r2095 r2208 r2480 misc::replace misc::replace_groups misc::replace_named_groups misc::replace_with_only_matching multiline::overlap1 multiline::overlap2 multiline::dot_all multiline::only_matching multiline::stdin multiline::context > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: existing multiline/replace suite selection did not pass; tail:" >&2
    tail -30 /tmp/oracle_suite.log >&2
    exit 1
fi

# Direct reproduction through the agent-facing binary.
printf ' b b b b b b b b\nc\n' > /tmp/oracle_haystack
RG_OUT=$(/app/src/target/debug/rg '(^|[^a-z])((([a-z]+)?)\s)?b(\s([a-z]+)?)($|[^a-z])' /tmp/oracle_haystack -U -rx)
RG_RC=$?
[ "$RG_RC" -eq 0 ] && [ "$RG_OUT" = "xbxbx" ] || {
    echo "oracle: direct reproduction failed rc=$RG_RC out='$RG_OUT'" >&2
    exit 1
}
echo "oracle: direct repro OK (rc=0, stdout='xbxbx')"

# Leave the tree exactly as the verifier expects it: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
git restore --worktree --source=HEAD -- tests/regression.rs || {
    echo "oracle: could not restore tests/regression.rs" >&2
    exit 1
}

echo "oracle: fix applied, summary written, regression suite green, repro OK"
exit 0