import org.apache.commons.lang3.StringUtils;

/**
 * Reproduction for the padding crash in this checkout.
 *
 * Demonstrates that a requested padding size from the extreme-negative end of
 * the int range must be a no-op returning the input string unchanged, and that
 * padding to a slightly larger size must still work.  On the as-shipped
 * (buggy) classes the first extreme-size call kills the JVM with an
 * uncatchable OutOfMemoryError; on fixed classes every check passes and the
 * process exits 0.
 *
 * Run with a capped heap so the failure is fast and deterministic:
 *   javac  -cp <classes> -d /tmp /app/repro/PadRepro.java
 *   java -Xmx256m -cp <classes>:/tmp PadRepro
 */
public class PadRepro {

    private static int checks;

    private static void expect(String what, String got, String want) {
        checks++;
        if (!java.util.Objects.equals(got, want)) {
            System.out.println("FAIL " + what + " got=" + got + " want=" + want);
            System.exit(1);
        }
        System.out.println("RESULT " + what + "=" + got);
    }

    public static void main(String[] args) {
        String s = "abc";
        // Requested sizes not greater than the string length must return the
        // string unchanged.  The extreme-negative sizes overflow the pad-count
        // arithmetic in this checkout and crash instead.
        expect("leftPad MIN", StringUtils.leftPad(s, Integer.MIN_VALUE, ' '), s);
        expect("leftPad MIN str", StringUtils.leftPad(s, Integer.MIN_VALUE, "-"), s);
        expect("leftPad MIN+1", StringUtils.leftPad(s, Integer.MIN_VALUE + 1, ' '), s);
        expect("rightPad MIN", StringUtils.rightPad(s, Integer.MIN_VALUE, '-'), s);
        expect("rightPad MIN str", StringUtils.rightPad(s, Integer.MIN_VALUE, "-"), s);
        expect("rightPad MIN+2", StringUtils.rightPad(s, Integer.MIN_VALUE + 2, ' '), s);
        // Sizes equal to or below the length are no-ops too.
        expect("leftPad len", StringUtils.leftPad(s, 3, ' '), s);
        expect("leftPad len-2", StringUtils.leftPad(s, 1, "x"), s);
        expect("rightPad len-1", StringUtils.rightPad(s, 2, 'x'), s);
        expect("rightPad neg", StringUtils.rightPad(s, -1, "x"), s);
        // Real padding must still work.
        expect("leftPad grows", StringUtils.leftPad(s, 5, '-'), "--abc");
        expect("rightPad grows", StringUtils.rightPad(s, 5, 'x'), "abcxx");

        System.out.println("ALL " + checks + " PAD CHECKS PASSED");
    }
}