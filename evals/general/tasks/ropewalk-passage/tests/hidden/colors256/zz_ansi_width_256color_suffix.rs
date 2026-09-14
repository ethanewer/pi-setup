#[test]
fn zz_ansi_width_256color_suffix() {
    // A 256-color sequence (38;5;196 - multiple colon-separated parameters
    // and a three-digit index) plus a reset, with plain text on both sides:
    // visible text "abcdefghi" is 9 columns; the buggy measurement returns 22.
    assert_eq!(9, "abc\x1B[38;5;196mdef\x1B[0mghi".width_graphemes());
}