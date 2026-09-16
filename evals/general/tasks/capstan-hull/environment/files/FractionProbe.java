package org.apache.commons.lang3.math;

/**
 * Direct reproduction for the spurious multiplication-overflow bug in
 * {@link Fraction}.
 *
 * <p>The headline case is exactly the one from the issue: multiplying the
 * fraction -1/46341 (already reduced) by 100/1000000 (not reduced, it is
 * 1/10000) must give -1/463410000. Every numerator and denominator involved
 * fits in an {@code int}, and so does the reduced product; the library
 * nonetheless throws {@code ArithmeticException: overflow: mulPos} because
 * it cancels common factors only across the two operands and assumes each
 * operand is already reduced.</p>
 *
 * <p>Additional checks cover the divideBy route (which delegates to
 * multiplyBy) and the guarantee that a genuinely overflowing product still
 * throws rather than being silently swallowed. The program exits 0 only when
 * every check passes.</p>
 *
 * <p>Compiled together with Fraction.java by /app/probe.sh.</p>
 */
public final class FractionProbe {

    private static int failures = 0;

    private static void check(final String label, final Fraction actual, final int wantNum, final int wantDen) {
        final boolean ok = actual.getNumerator() == wantNum && actual.getDenominator() == wantDen;
        System.out.println((ok ? "PASS " : "FAIL ") + label
                + " (got " + actual.getNumerator() + "/" + actual.getDenominator()
                + ", want " + wantNum + "/" + wantDen + ")");
        if (!ok) {
            failures++;
        }
    }

    private static void checkThrows(final String label, final java.util.concurrent.Callable<Fraction> call) {
        try {
            final Fraction got = call.call();
            System.out.println("FAIL " + label + " (expected ArithmeticException, got " + got + ")");
            failures++;
        } catch (final ArithmeticException expected) {
            System.out.println("PASS " + label + " (threw " + expected + ")");
        } catch (final Exception unexpected) {
            System.out.println("FAIL " + label + " (expected ArithmeticException, got " + unexpected + ")");
            failures++;
        }
    }

    public static void main(final String[] args) {
        // ---- the headline reproduction from the issue ----
        try {
            final Fraction r = Fraction.getFraction(-1, 46341).multiplyBy(Fraction.getFraction(100, 1000000));
            System.out.println("RESULT=" + r.getNumerator() + "/" + r.getDenominator());
            check("multiply: (-1/46341) * (100/1000000)", r, -1, 463410000);
        } catch (final ArithmeticException e) {
            System.out.println("THREW " + e);
            System.exit(1);
        }

        // ---- divideBy routes through the same code path ----
        //  (-1/46341) / (1000000/100) == (-1/46341) * (100/1000000)
        try {
            final Fraction r = Fraction.getFraction(-1, 46341).divideBy(Fraction.getFraction(1000000, 100));
            check("divide: (-1/46341) / (1000000/100)", r, -1, 463410000);
        } catch (final ArithmeticException e) {
            System.out.println("THREW " + e);
            failures++;
        }

        // ---- both operands unreduced ----
        //  12/556092 == 1/46341 and 125/5792500 == 1/46340
        try {
            final Fraction r = Fraction.getFraction(12, 556092).multiplyBy(Fraction.getFraction(125, 5792500));
            check("multiply: (12/556092) * (125/5792500) [both unreduced]", r, 1, 2147441940);
        } catch (final ArithmeticException e) {
            System.out.println("THREW " + e);
            failures++;
        }

        // ---- reduced operands still multiply exactly as before ----
        final Fraction r2 = Fraction.getFraction(2, 7).multiplyBy(Fraction.getFraction(3, 5));
        check("multiply: (2/7) * (3/5) [already reduced]", r2, 6, 35);

        // ---- a genuinely overflowing product must still throw ----
        checkThrows("guard: (1/50000) * (1/50000) must still overflow",
                () -> Fraction.getFraction(1, 50000).multiplyBy(Fraction.getFraction(1, 50000)));
        checkThrows("guard: (1/46341) * (1/46341) cross-product must still overflow",
                () -> Fraction.getFraction(1, 46341).multiplyBy(Fraction.getFraction(1, Integer.MAX_VALUE - 1)));

        if (failures > 0) {
            System.out.println("RESULT=false (" + failures + " check(s) failed)");
            System.exit(1);
        }
        System.out.println("RESULT=true (all fraction multiplication checks passed)");
    }
}