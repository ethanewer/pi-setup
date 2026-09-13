#!/bin/bash
# Oracle for chainplate-hull: applies the one-function fix to the real
# starship tree at /app/src (an empty prompt format textgroup must emit one
# zero-width segment carrying the textgroup's style, so prev_fg/prev_bg
# references in later segments resolve), writes /app/summary.md, then proves
# the work with the project's own test tooling: the upstream regression
# tests baked at /opt/golden (planted into the inline mod tests of
# src/formatter/string_formatter.rs with /app/plant_golden.py), a targeted
# subset of the project's own existing string-formatter unit tests, and the
# byte-exact CLI reproduction. All offline; reads only /app, /solution and
# /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/opt/cargo/bin:$PATH

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied empty-textgroup fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: in prompt format strings, an empty textgroup whose only purpose is to
set a color, such as `[](bg:#9A348E)`, was discarded entirely at parse time:
`parse_textgroup` parsed the group's style and forwarded it to
`parse_format`, which produced no segments for an empty format. That meant
such a group could never establish the style that a later segment inherits
through `prev_fg`/`prev_bg` references. Concretely, a format like
`[](bg:red)[X](bg:prev_bg)` rendered the `X` with no background at all,
because the preceding empty group emitted no segment for `prev_bg` to refer
back to, so the CLI printed a bare `X` (single byte, no ANSI escapes).

Fix: in `parse_textgroup` (src/formatter/string_formatter.rs), when the
group's format is empty, return one zero-width styled segment carrying the
group's (transposed) parsed style instead of recursing into `parse_format`.
Later segments that reference `prev_fg`/`prev_bg` now resolve against that
segment, so `[](bg:red)[X](bg:prev_bg)` renders `\x1b[41mX\x1b[0m` (X on a
red background). Groups with non-empty formats are unchanged.

Verification: the project's own test harness (compiled offline with
`cargo test --no-run --locked`) passes the three upstream regression tests
for this bug (`test_empty_textgroup_with_style`,
`test_empty_textgroup_without_style`,
`test_empty_textgroup_propagates_prev_bg`, planted from /opt/golden) as well
as a targeted selection of the project's existing string-formatter unit
tests (test_default_style, test_nested_textgroup, test_styled_variable_as_text,
test_style_variable_nested, test_meta_variable, test_conditional,
test_nested_conditional, test_bash_escape). The CLI reproduction
(`STARSHIP_CONFIG` with `format = "[](bg:red)[X](bg:prev_bg)"`) prints
`\x1b[41mX\x1b[0m` byte-exact and exits 0.
MD

# Prove the fix with the project's own machinery: plant the upstream
# regression tests (golden bytes from /opt/golden, already in the image)
# into the inline mod tests, rebuild offline, and run the targeted harness
# subset.
python3 /app/plant_golden.py /app/src/src/formatter/string_formatter.rs \
    /opt/golden/string_formatter_tests.rs || {
    echo "oracle: could not plant golden tests" >&2
    exit 1
}

if ! cargo build --locked > /tmp/oracle_build1.log 2>&1; then
    echo "oracle: cargo build failed; tail:" >&2
    tail -30 /tmp/oracle_build1.log >&2
    exit 1
fi
if ! cargo test --no-run --locked > /tmp/oracle_build2.log 2>&1; then
    echo "oracle: cargo test --no-run failed; tail:" >&2
    tail -30 /tmp/oracle_build2.log >&2
    exit 1
fi

GOLDEN="test_empty_textgroup_with_style test_empty_textgroup_without_style test_empty_textgroup_propagates_prev_bg"
if ! cargo test --locked -- $GOLDEN > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: golden tests did not pass; tail:" >&2
    tail -30 /tmp/oracle_golden.log >&2
    exit 1
fi
for t in $GOLDEN; do
    grep -q "$t \.\.\. ok" /tmp/oracle_golden.log || {
        echo "oracle: golden test $t did not actually run and pass" >&2
        exit 1
    }
done

EXISTING="test_default_style test_nested_textgroup test_styled_variable_as_text test_style_variable_nested test_meta_variable test_conditional test_nested_conditional test_bash_escape"
if ! cargo test --locked -- $EXISTING > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: existing formatter suite selection did not pass; tail:" >&2
    tail -30 /tmp/oracle_suite.log >&2
    exit 1
fi
for t in $EXISTING; do
    grep -q "$t \.\.\. ok" /tmp/oracle_suite.log || {
        echo "oracle: existing test $t did not actually run and pass" >&2
        exit 1
    }
done

# Byte-exact CLI reproduction through the agent-facing binary.
export STARSHIP_CONFIG=/tmp/oracle_fmt.cfg
printf 'format = "[](bg:red)[X](bg:prev_bg)"\nadd_newline = false\n' > "$STARSHIP_CONFIG"
if ! cmp -s <( ./target/debug/starship prompt ) <( printf '\033[41mX\033[0m' ); then
    echo "oracle: CLI repro bytes mismatch;" >&2
    ./target/debug/starship prompt | od -An -c >&2
    exit 1
fi
echo "oracle: CLI repro OK (bytes: ESC [ 4 1 m X ESC [ 0 m)"

echo "oracle: fix applied, summary written, regression suite green, repro OK"
exit 0