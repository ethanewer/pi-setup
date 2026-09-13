#!/usr/bin/env python3
"""Applies the spurious-overflow fix to Fraction.multiplyBy in commons-lang.

The bug: multiplyBy cancels common factors only ACROSS the two operands
(Knuth 4.5.1 cross-gcd) and assumes each operand is already reduced. A factor
shared inside a single unreduced operand therefore survives into the
intermediate int product and can overflow even when the reduced result fits
in an int (e.g. -1/46341 * 100/1000000 = -1/463410000 throws
"overflow: mulPos").

The fix reduces both operands into locals first, then performs the same
Knuth cross-gcd cancellation, so an internal factor can no longer overflow
the intermediate products. divideBy and pow route through multiplyBy and are
fixed at the same time.

Usage: fix_fraction.py <path-to-Fraction.java>
"""

import sys


FIND = """        final int d1 = greatestCommonDivisor(numerator, fraction.denominator);
        final int d2 = greatestCommonDivisor(fraction.numerator, denominator);
        return getReducedFraction(mulAndCheck(numerator / d1, fraction.numerator / d2), mulPosAndCheck(denominator / d2, fraction.denominator / d1));"""

REPLACE = """        // Reduce both operands first: the cross-gcd below cancels the cross terms only, so a
        // factor shared inside an unreduced operand survives into the product and can overflow
        // an int even when the reduced result fits.
        final int thisGcd = greatestCommonDivisor(numerator, denominator);
        final int thatGcd = greatestCommonDivisor(fraction.numerator, fraction.denominator);
        final int thisNumerator = numerator / thisGcd;
        final int thisDenominator = denominator / thisGcd;
        final int thatNumerator = fraction.numerator / thatGcd;
        final int thatDenominator = fraction.denominator / thatGcd;
        final int d1 = greatestCommonDivisor(thisNumerator, thatDenominator);
        final int d2 = greatestCommonDivisor(thatNumerator, thisDenominator);
        return getReducedFraction(mulAndCheck(thisNumerator / d1, thatNumerator / d2), mulPosAndCheck(thisDenominator / d2, thatDenominator / d1));"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_fraction.py <path-to-Fraction.java>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    if REPLACE in src:
        print("fix already present in %s" % path)
        return 0
    if FIND not in src:
        print("expected buggy multiplyBy block not found in %s; aborting" % path, file=sys.stderr)
        return 3
    src = src.replace(FIND, REPLACE, 1)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)
    print("patched %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())