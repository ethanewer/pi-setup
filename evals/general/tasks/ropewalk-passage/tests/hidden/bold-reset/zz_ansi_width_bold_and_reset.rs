#[test]
fn zz_ansi_width_bold_and_reset() {
    // Bold SGR codes (no parameters) flanking plain text: the visible text
    // "hello" is 5 columns; the buggy measurement counts the ESC[1m and
    // ESC[0m bytes as printable (returns 13).
    assert_eq!(5, "\x1B[1mhello\x1B[0m".width_graphemes());
}