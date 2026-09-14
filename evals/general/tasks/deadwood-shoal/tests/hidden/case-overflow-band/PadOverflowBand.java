import org.apache.commons.lang3.StringUtils;

/**
 * Hidden case: overflow-band requested sizes across many string lengths and
 * both pad kinds (char and String), all no-op sizes that the upstream
 * regression test does not use.
 *
 * For length L the arithmetic `pads = size - L` overflows exactly when
 * size is in [Integer.MIN_VALUE, Integer.MIN_VALUE + L - 1]; every such size
 * must be a no-op returning the string unchanged.  On the buggy classes the
 * first call of the sweep kills the JVM with OutOfMemoryError; on fixed
 * classes every check passes and the process exits 0.
 *
 * Run with a capped heap so the pre-fix failure is fast and deterministic:
 *   javac -cp <classes> -d /tmp PadOverflowBand.java
 *   java -Xmx256m -cp <classes>:/tmp PadOverflowBand
 */
public class PadOverflowBand {

    private static final String[] STRINGS = {
        "a",
        "xy",
        "hello",
        "abcdefgh",
        "the slow brown fox",
        "0123456789abcdef0123456789abcdef",
    };

    private static int checks;

    private static void expect(String what, String got, String want) {
        checks++;
        if (!java.util.Objects.equals(got, want)) {
            System.out.println("FAIL " + what + " got=" + got + " want=" + want);
            System.exit(1);
        }
    }

    public static void main(String[] args) {
        for (String s : STRINGS) {
            int len = s.length();
            int[] sizes;
            if (len >= 2) {
                sizes = new int[] {
                    Integer.MIN_VALUE,
                    Integer.MIN_VALUE + 1,
                    Integer.MIN_VALUE + len - 1,
                };
            } else {
                sizes = new int[] {
                    Integer.MIN_VALUE,
                    Integer.MIN_VALUE + len - 1,
                };
            }
            for (int size : sizes) {
                if (size >= len) {
                    System.out.println("FAIL internal: size " + size
                            + " not below length " + len);
                    System.exit(1);
                }
                expect("leftPad(" + q(s) + "," + size + ",'x')",
                        StringUtils.leftPad(s, size, 'x'), s);
                expect("leftPad(" + q(s) + "," + size + ",\"xy\")",
                        StringUtils.leftPad(s, size, "xy"), s);
                expect("rightPad(" + q(s) + "," + size + ",'x')",
                        StringUtils.rightPad(s, size, 'x'), s);
                expect("rightPad(" + q(s) + "," + size + ",\"xy\")",
                        StringUtils.rightPad(s, size, "xy"), s);
            }
            // Non-overflowing no-op boundary on the same strings.
            expect("leftPad(" + q(s) + "," + (len - 1) + ",\"xy\")",
                    StringUtils.leftPad(s, len - 1, "xy"), s);
        }
        System.out.println("PASS " + checks + " overflow-band checks");
    }

    private static String q(String s) {
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
}