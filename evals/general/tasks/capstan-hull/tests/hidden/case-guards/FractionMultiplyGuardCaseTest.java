package org.apache.commons.lang3.math;

import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

/**
 * Authored hidden guard cases for the spurious fraction overflow fix
 * (capstan-hull). A correct fix must eliminate only the SPURIOUS overflow:
 * a product whose reduced value genuinely exceeds Integer.MAX_VALUE must
 * still throw, and the zero / identity / sign behaviour of the fixed method
 * must be unchanged from the pristine tree.
 */
class FractionMultiplyGuardCaseTest {

    @Test
    void genuineOverflowStillThrows() {
        // 1/50000 * 1/50000 == 1/2500000000 > Integer.MAX_VALUE: must throw.
        assertThrows(ArithmeticException.class,
                () -> Fraction.getFraction(1, 50000).multiplyBy(Fraction.getFraction(1, 50000)));
        // 46341 * 2147483646 > Integer.MAX_VALUE: the cross product must
        // still overflow rather than being silently suppressed.
        assertThrows(ArithmeticException.class,
                () -> Fraction.getFraction(1, 46341).multiplyBy(Fraction.getFraction(1, Integer.MAX_VALUE - 1)));
        // Division with a genuinely overflowing quotient still throws:
        // (1/46341) / (1000000/2147483) has reduced denominator
        // 46341000000 > Integer.MAX_VALUE.
        assertThrows(ArithmeticException.class,
                () -> Fraction.getFraction(1, 46341).divideBy(Fraction.getFraction(1000000, 2147483)));
    }

    @Test
    void zeroBehaviourUnchanged() {
        assertSame(Fraction.ZERO, Fraction.getFraction(100, 1000000).multiplyBy(Fraction.ZERO));
        assertSame(Fraction.ZERO, Fraction.ZERO.multiplyBy(Fraction.getFraction(46341, 1000000)));
    }

    @Test
    void identityBehaviourUnchanged() {
        final Fraction r = Fraction.getFraction(355, 113).multiplyBy(Fraction.ONE);
        assertEquals(355, r.getNumerator());
        assertEquals(113, r.getDenominator());
    }

    @Test
    void reducedOperandsMultiplyAsBefore() {
        final Fraction r = Fraction.getFraction(2, 7).multiplyBy(Fraction.getFraction(3, 5));
        assertEquals(6, r.getNumerator());
        assertEquals(35, r.getDenominator());
    }
}