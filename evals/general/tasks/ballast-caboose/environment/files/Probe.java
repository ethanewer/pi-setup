package org.apache.commons.lang3;

/**
 * Self-contained reproduction for the range-containment boundary bug.
 *
 * Compiled together with CharRange.java by /app/probe.sh. Asserts the
 * mathematically correct containment answers for negated ranges whose
 * excluded block touches a domain boundary; exits 0 only when every check
 * passes.
 */
public final class Probe {

    private static int failures = 0;

    private static void check(final String label, final boolean expected, final boolean actual) {
        if (expected == actual) {
            System.out.println("PASS " + label + " (was " + actual + ")");
        } else {
            System.out.println("FAIL " + label + " (expected " + expected + ", was " + actual + ")");
            failures++;
        }
    }

    public static void main(final String[] args) {
        final char MAX = Character.MAX_VALUE;
        final char NUL = 0;

        // isNotIn(0, MAX) denotes the empty set: contained by anything.
        check("is('x').contains(isNotIn(0, MAX))", true,
                CharRange.is('x').contains(CharRange.isNotIn(NUL, MAX)));
        // ... in particular by a single interior character range.
        check("isIn(1000, 2000).contains(isNotIn(0, MAX))", true,
                CharRange.isIn((char) 1000, (char) 2000).contains(CharRange.isNotIn(NUL, MAX)));
        // ... and by the full domain.
        check("isIn(0, MAX).contains(isNotIn(0, MAX))", true,
                CharRange.isIn(NUL, MAX).contains(CharRange.isNotIn(NUL, MAX)));

        // isNotIn(0, 'a'-1) denotes ['a', MAX]: contained by any range that
        // starts no later than 'a' and ends at MAX.
        check("isIn('a', MAX).contains(isNotIn(0, 'a'-1))", true,
                CharRange.isIn('a', MAX).contains(CharRange.isNotIn(NUL, (char) ('a' - 1))));
        check("isIn('Z', MAX).contains(isNotIn(0, 'a'-1))", true,
                CharRange.isIn('Z', MAX).contains(CharRange.isNotIn(NUL, (char) ('a' - 1))));
        check("isIn('b', MAX).contains(isNotIn(0, 'a'-1))", false,
                CharRange.isIn('b', MAX).contains(CharRange.isNotIn(NUL, (char) ('a' - 1))));

        // isNotIn('b', MAX) denotes [0, 'a']: contained by any range that
        // starts at 0 and extends at least to 'a'.
        check("isIn(0, 'a').contains(isNotIn('b', MAX))", true,
                CharRange.isIn(NUL, 'a').contains(CharRange.isNotIn('b', MAX)));
        check("isIn(0, 'b').contains(isNotIn('b', MAX))", true,
                CharRange.isIn(NUL, 'b').contains(CharRange.isNotIn('b', MAX)));
        check("isIn(1, 'a').contains(isNotIn('b', MAX))", false,
                CharRange.isIn((char) 1, 'a').contains(CharRange.isNotIn('b', MAX)));

        // Interior excluded block: still only containable by the full domain.
        check("isIn(0, MAX).contains(isNot('c'))", true,
                CharRange.isIn(NUL, MAX).contains(CharRange.isNot('c')));
        check("is('x').contains(isNot('x'))", false,
                CharRange.is('x').contains(CharRange.isNot('x')));

        // Ordinary (non-negated) containment unchanged.
        check("isIn('a','z').contains(isIn('b','y'))", true,
                CharRange.isIn('a', 'z').contains(CharRange.isIn('b', 'y')));
        check("isIn('a','z').contains(isIn('A','Z'))", false,
                CharRange.isIn('a', 'z').contains(CharRange.isIn('A', 'Z')));

        // Negated receiver paths unchanged.
        check("isNotIn('a','z').contains('x')", false,
                CharRange.isNotIn('a', 'z').contains('x'));
        check("isNotIn('a','z').contains('A')", true,
                CharRange.isNotIn('a', 'z').contains('A'));

        if (failures > 0) {
            System.out.println("RESULT=false (" + failures + " check(s) failed)");
            System.exit(1);
        }
        System.out.println("RESULT=true (all containment checks passed)");
    }
}