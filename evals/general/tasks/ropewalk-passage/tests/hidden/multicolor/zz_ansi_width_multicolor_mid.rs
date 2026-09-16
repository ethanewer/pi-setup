#[test]
fn zz_ansi_width_multicolor_mid() {
    // Two foreground color codes interleaved in the middle of the text
    // ("re" red, "gre" green, reset, "en"): visible text "regreen" is 7
    // columns; the buggy measurement returns 18.
    assert_eq!(7, "\x1B[31mre\x1B[32mgre\x1B[0men".width_graphemes());
}