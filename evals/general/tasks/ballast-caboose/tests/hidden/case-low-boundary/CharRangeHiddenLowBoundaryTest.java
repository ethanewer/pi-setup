package org.apache.commons.lang3;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

/**
 * Hidden cases for the negated-argument containment fix: excluded blocks that
 * START at the low domain boundary (0). The complement of isNotIn(0, k) is
 * the single interval [k+1, MAX_VALUE]. Inputs deliberately avoid the ones
 * used by the upstream regression test ('a' based).
 */
class CharRangeHiddenLowBoundaryTest {

    @Test
    void testComplementOfSingletonAtZero() {
        // isNotIn(0, 0) denotes [1, MAX_VALUE]
        final CharRange fromOne = CharRange.isNotIn((char) 0, (char) 0);
        assertTrue(CharRange.isIn((char) 1, Character.MAX_VALUE).contains(fromOne));
        assertTrue(CharRange.isIn((char) 1, (char) 0xFFFF).contains(fromOne));
        assertFalse(CharRange.isIn((char) 2, Character.MAX_VALUE).contains(fromOne));
        assertFalse(CharRange.isIn((char) 1, (char) 0x00FF).contains(fromOne));
        assertTrue(CharRange.isIn((char) 0, Character.MAX_VALUE).contains(fromOne));
    }

    @Test
    void testComplementOfMinThroughFirstTwo() {
        // isNotIn(0, 1) denotes [2, MAX_VALUE]
        final CharRange fromTwo = CharRange.isNotIn((char) 0, (char) 1);
        assertTrue(CharRange.isIn((char) 2, Character.MAX_VALUE).contains(fromTwo));
        assertFalse(CharRange.isIn((char) 3, Character.MAX_VALUE).contains(fromTwo));
        assertFalse(CharRange.isIn((char) 2, (char) 0x00FF).contains(fromTwo));
        assertTrue(CharRange.isIn((char) 0, Character.MAX_VALUE).contains(fromTwo));
    }

    @Test
    void testComplementOfMinThroughByteRange() {
        // isNotIn(0, 0xFF) denotes [0x100, MAX_VALUE]
        final CharRange from256 = CharRange.isNotIn((char) 0, (char) 0xFF);
        assertTrue(CharRange.isIn((char) 0x100, Character.MAX_VALUE).contains(from256));
        assertFalse(CharRange.isIn((char) 0x101, Character.MAX_VALUE).contains(from256));
        assertFalse(CharRange.isIn((char) 0x100, (char) 0xFFFE).contains(from256));
        assertTrue(CharRange.isIn((char) 0, Character.MAX_VALUE).contains(from256));
    }

    @Test
    void testComplementOfMinThroughFirstByteBounds() {
        // isNotIn(0, 0x100) denotes [0x101, MAX_VALUE]
        final CharRange from257 = CharRange.isNotIn((char) 0, (char) 0x100);
        assertTrue(CharRange.isIn((char) 0x101, Character.MAX_VALUE).contains(from257));
        assertFalse(CharRange.isIn((char) 0x102, Character.MAX_VALUE).contains(from257));
        assertFalse(CharRange.isIn((char) 0x101, (char) 0xFFFE).contains(from257));
    }
}