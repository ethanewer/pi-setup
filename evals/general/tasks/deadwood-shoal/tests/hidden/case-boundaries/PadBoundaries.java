import org.apache.commons.lang3.StringUtils;

/**
 * Hidden case: exact boundary sizes around each string length, unicode
 * strings, embedded NUL bytes, and the null / empty-padStr contract - inputs
 * the upstream regression test does not use.
 *
 * Every requested size not greater than the string length must return the
 * string unchanged (including the exact-length and overflow-band boundaries);
 * padding to a larger size must still pad correctly; null input must stay
 * null on all four overloads; null/empty padStr must fall back to a single
 * space.  On the buggy classes the first overflow-band call kills the JVM
 * with OutOfMemoryError; on fixed classes every check passes.
 */
public class PadBoundaries {

    private static final String[] STRINGS = {
        "\u00fc",                                     // "ü"
        "h\u00e9llo",                                 // "héllo"
        "a\u0000b\u0000c\u0000",                      // embedded NULs
        "the quick brown fox jumps over the lazy dog",
    };

    private static int checks;

    private static void expect(String what, Object got, Object want) {
        checks++;
        if (!java.util.Objects.equals(got, want)) {
            System.out.println("FAIL " + what + " got=" + got + " want=" + want);
            System.exit(1);
        }
    }

    public static void main(String[] args) {
        for (String s : STRINGS) {
            int len = s.length();
            // Overflow band at this length: no-op sizes that crash the
            // buggy build with an uncatchable OutOfMemoryError.
            int[] crash = {
                Integer.MIN_VALUE,
                Integer.MIN_VALUE + len - 1,
            };
            for (int size : crash) {
                expect("leftPad", StringUtils.leftPad(s, size, 'q'), s);
                expect("leftPad", StringUtils.leftPad(s, size, "q!"), s);
                expect("rightPad", StringUtils.rightPad(s, size, 'q'), s);
                expect("rightPad", StringUtils.rightPad(s, size, "q!"), s);
            }
            // Exact-length and len-1 sizes are no-ops too.
            expect("leftPad len", StringUtils.leftPad(s, len, 'q'), s);
            expect("rightPad len", StringUtils.rightPad(s, len, "q!"), s);
            expect("leftPad len-1", StringUtils.leftPad(s, len - 1, "q!"), s);
            // Positive padding must still work exactly.
            expect("leftPad +2",
                    StringUtils.leftPad(s, len + 2, 'z'),
                    "zz" + s);
            expect("rightPad +2",
                    StringUtils.rightPad(s, len + 2, 'z'),
                    s + "zz");
        }
        // Null input -> null output on all four overloads.
        expect("leftPad null c", StringUtils.leftPad(null, 5, 'x'), null);
        expect("leftPad null s", StringUtils.leftPad(null, 5, "x"), null);
        expect("rightPad null c", StringUtils.rightPad(null, 5, 'x'), null);
        expect("rightPad null s", StringUtils.rightPad(null, 5, "x"), null);
        // null / empty padStr fall back to a single space (behaviour kept).
        expect("leftPad null pad", StringUtils.leftPad("ab", 5, (String) null), "   ab");
        expect("leftPad empty pad", StringUtils.leftPad("ab", 5, ""), "   ab");
        expect("rightPad null pad", StringUtils.rightPad("ab", 5, (String) null), "ab   ");
        expect("rightPad empty pad", StringUtils.rightPad("ab", 5, ""), "ab   ");
        // Extreme no-op with an empty padStr (overflow band again).
        expect("leftPad MIN empty pad",
                StringUtils.leftPad("ab", Integer.MIN_VALUE, ""), "ab");

        System.out.println("PASS " + checks + " boundary checks");
    }
}