#!/bin/bash
# Oracle for ropewalk-passage: applies the real upstream fix for
# starship/starship issue #6861 (ANSI color escape sequences are counted as
# printable columns by the grapheme-width measurement the explain layout
# pads against) to the checkout at /app/src, appends the required
# reproduction unit test, writes /app/summary.md, and proves the fix with
# the project's own unit-test harness. Reads only /app, /solution, /opt.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/opt/cargo/bin:$PATH

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to the checked-out tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied ANSI-width fix patch"

# Append the required reproduction unit test. It is self-contained and must
# fail on the pristine tree (the buggy measurement returns 17 columns for
# this string) and pass once the fix is in (visible text is 11 columns).
cat >> src/print.rs <<'EOF'

#[test]
fn repro_ansi_width_magenta_visible_width() {
    assert_eq!(11, "\x1B[35;6mnormal text".width_graphemes());
}
EOF

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: the grapheme-width measurement the `starship explain` breakdown layout
relies on counts each byte of an embedded ANSI color escape sequence
(`ESC [ params m`) as if it were a printable column. Whenever a module
value carries color codes (for example pre-colored output from a custom
command), the measurement returns a width larger than the visible text, so
explain pads that row with too few spaces and the shared description column
drifts out of alignment with the rows that have no color codes.

Reproduction: a unit test asserting that a string whose visible text is
`normal text`, carrying a leading magenta color code (`\x1B[35;6mnormal
text`), measures 11 columns, fails on the untouched tree (the measurement
returns 17) and passes once the fix is in.

Fix: precompile the ANSI CSI color-sequence regex (`\x1B\[[0-9;]*m`),
strip those sequences from the string before measuring grapheme widths, so
non-printing escape sequences no longer inflate the measured width.
Plain text keeps measuring exactly as before.

Verification: `cargo test --locked --offline -- width` (the project's own
width unit tests, including the reproduction above) is green on the fixed
tree; the same reproduction fails against the pristine code.
MD

# Prove the fix with the project's own machinery: run the width-filtered
# unit tests offline on the fixed tree (includes the reproduction above and
# the project's pre-existing width tests).
if ! cargo test --locked --offline -- width > /tmp/oracle_test.log 2>&1; then
    tail -40 /tmp/oracle_test.log >&2
    echo "oracle: width unit tests failed after the fix" >&2
    exit 1
fi

echo "oracle: fix applied, reproduction written, summary written, width tests green"
exit 0