package org.apache.commons.lang3.math;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.math.BigInteger;

import org.junit.jupiter.api.Test;

/**
 * Authored hidden cases for the spurious fraction-multiplication overflow
 * (capstan-hull). These exercise the {@link Fraction#multiplyBy} code path
 * from inputs the upstream regression test does not use: products where
 * BOTH operands are unreduced and large, a product where one unreduced
 * operand is negative, and a product of two already-reduced operands whose
 * true value sits just below Integer.MAX_VALUE.
 *
 * <p>Every expected value is computed independently with BigInteger
 * arithmetic on the raw numerator/denominator pairs, then reduced, so a
 * passing test proves the Fraction result is the mathematically correct
 * reduced value — not just that no exception was thrown.</p>
 */
class FractionUnreducedMultiplyCaseTest {

    private static void assertReducedProduct(final Fraction a, final Fraction b) {
        BigInteger num = BigInteger.valueOf(a.getNumerator()).multiply(BigInteger.valueOf(b.getNumerator()));
        BigInteger den = BigInteger.valueOf(a.getDenominator()).multiply(BigInteger.valueOf(b.getDenominator()));
        final BigInteger g = num.gcd(den);
        if (g.signum() != 0) {
            num = num.divide(g);
            den = den.divide(g);
        }
        // Fraction normalises a negative denominator onto the numerator.
        if (den.signum() < 0) {
            num = num.negate();
            den = den.negate();
        }
        final Fraction r = a.multiplyBy(b);
        assertEquals(num.longValueExact(), (long) r.getNumerator());
        assertEquals(den.longValueExact(), (long) r.getDenominator());
    }

    @Test
    void bothOperandsUnreducedNearIntLimit() {
        // 12/556092 reduces to 1/46341; 125/5792500 reduces to 1/46340.
        // The reduced product 1/2147441940 fits an int; the unreduced
        // product 1500/3221141310000 is far beyond it.
        assertReducedProduct(Fraction.getFraction(12, 556092), Fraction.getFraction(125, 5792500));
    }

    @Test
    void oneUnreducedOperandNegative() {
        // -7/60000 * 150/750000: 150/750000 == 1/5000, product == -7/300000000.
        assertReducedProduct(Fraction.getFraction(-7, 60000), Fraction.getFraction(150, 750000));
    }

    @Test
    void reducedOperandsJustBelowIntLimit() {
        // 1/46341 * 1/46340 == 1/2147441940, already reduced, still fits.
        assertReducedProduct(Fraction.getFraction(1, 46341), Fraction.getFraction(1, 46340));
    }
}