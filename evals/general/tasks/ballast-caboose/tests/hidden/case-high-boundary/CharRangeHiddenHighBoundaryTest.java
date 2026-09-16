package org.apache.commons.lang3;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

/**
 * Hidden cases for the negated-argument containment fix: excluded blocks that
 * END at the high domain boundary (Character.MAX_VALUE). The complement of
 * isNotIn(k, MAX) is the single interval [0, k-1]. Inputs deliberately avoid
 * the ones used by the upstream regression test ('b' based).
 */
class CharRangeHiddenHighBoundaryTest {

    @Test
    void testComplementOfTopSingleton() {
        // isNotIn(MAX, MAX) denotes [0, 0xFFFE]
        final CharRange upToMaxMinus1 = CharRange.isNotIn(Character.MAX_VALUE, Character.MAX_VALUE);
        assertTrue(CharRange.isIn((char) 0, (char) 0xFFFE).contains(upToMaxMinus1));
        assertFalse(CharRange.isIn((char) 0, (char) 0xFFFD).contains(upToMaxMinus1));
        assertFalse(CharRange.isIn((char) 1, (char) 0xFFFE).contains(upToMaxMinus1));
        assertTrue(CharRange.isIn((char) 0, Character.MAX_VALUE).contains(upToMaxMinus1));
    }

    @Test
    void testComplementOfTopTwo() {
        // isNotIn(0xFFFE, MAX) denotes [0, 0xFFFD]
        final CharRange upToMaxMinus2 = CharRange.isNotIn((char) 0xFFFE, Character.MAX_VALUE);
        assertTrue(CharRange.isIn((char) 0, (char) 0xFFFD).contains(upToMaxMinus2));
        assertFalse(CharRange.isIn((char) 0, (char) 0xFFFC).contains(upToMaxMinus2));
        assertFalse(CharRange.isIn((char) 1, (char) 0xFFFD).contains(upToMaxMinus2));
        assertTrue(CharRange.isIn((char) 0, Character.MAX_VALUE).contains(upToMaxMinus2));
    }

    @Test
    void testComplementOfHighByteRange() {
        // isNotIn(0x0100, MAX) denotes [0, 0xFF]
        final CharRange upTo255 = CharRange.isNotIn((char) 0x0100, Character.MAX_VALUE);
        assertTrue(CharRange.isIn((char) 0, (char) 0xFF).contains(upTo255));
        assertFalse(CharRange.isIn((char) 0, (char) 0xFE).contains(upTo255));
        assertFalse(CharRange.isIn((char) 1, (char) 0xFF).contains(upTo255));
        assertTrue(CharRange.isIn((char) 0, Character.MAX_VALUE).contains(upTo255));
    }

    @Test
    void testComplementBeyondLetters() {
        // isNotIn('{', MAX) -- '{' == 'z' + 1 -- denotes [0, 'z']
        final CharRange upToZ = CharRange.isNotIn((char) ('z' + 1), Character.MAX_VALUE);
        assertTrue(CharRange.isIn((char) 0, 'z').contains(upToZ));
        assertFalse(CharRange.isIn((char) 0, 'y').contains(upToZ));
        assertFalse(CharRange.isIn((char) 1, 'z').contains(upToZ));
        assertTrue(CharRange.isIn((char) 0, Character.MAX_VALUE).contains(upToZ));
    }
}