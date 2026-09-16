package org.apache.commons.lang3.math;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.math.BigInteger;

import org.junit.jupiter.api.Test;

/**
 * Authored hidden cases for the spurious fraction overflow (capstan-hull),
 * reaching the broken code through {@link Fraction#divideBy} and
 * {@link Fraction#pow}, which both route into the same multiplication code
 * path. The divisor is unreduced in every case, with numerators and
 * denominators that the upstream regression test does not use. Expected
 * values are computed independently with BigInteger arithmetic.
 */
class FractionUnreducedDivideCaseTest {

    private static void assertReducedQuotient(final Fraction a, final Fraction d) {
        BigInteger num = BigInteger.valueOf(a.getNumerator()).multiply(BigInteger.valueOf(d.getDenominator()));
        BigInteger den = BigInteger.valueOf(a.getDenominator()).multiply(BigInteger.valueOf(d.getNumerator()));
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
        final Fraction r = a.divideBy(d);
        assertEquals(num.longValueExact(), (long) r.getNumerator());
        assertEquals(den.longValueExact(), (long) r.getDenominator());
    }

    @Test
    void divideByUnreducedDivisor() {
        // (3/46341) / (1000000/100): the unreduced divisor 1000000/100 equals
        // 10000/1, so the quotient is (3/46341)/10000 == 1/154470000.
        assertReducedQuotient(Fraction.getFraction(3, 46341), Fraction.getFraction(1000000, 100));
    }

    @Test
    void divideByUnreducedPrimeDenominator() {
        // (5/65537) / (200000/50): 200000/50 equals 4000/1, quotient is
        // (5/65537)/4000 == 1/52429600.
        assertReducedQuotient(Fraction.getFraction(5, 65537), Fraction.getFraction(200000, 50));
    }

    @Test
    void powOfUnreducedFraction() {
        // pow routes through multiplyBy; the result must be the exact square.
        // (100/1000000)^2 == 1/100000000, and the intermediate product of
        // the unreduced operand with itself must not spuriously overflow.
        final BigInteger num = BigInteger.valueOf(100).pow(2);
        final BigInteger den = BigInteger.valueOf(1000000).pow(2);
        final BigInteger g = num.gcd(den);
        final Fraction r = Fraction.getFraction(100, 1000000).pow(2);
        assertEquals(num.divide(g).longValueExact(), (long) r.getNumerator());
        assertEquals(den.divide(g).longValueExact(), (long) r.getDenominator());
    }

    @Test
    void divideByUnreducedDivisorNegative() {
        // (7/46341) / (-1000000/100): sign stays with the numerator of the
        // quotient, value is -7/463410000.
        assertReducedQuotient(Fraction.getFraction(7, 46341), Fraction.getFraction(-1000000, 100));
    }
}