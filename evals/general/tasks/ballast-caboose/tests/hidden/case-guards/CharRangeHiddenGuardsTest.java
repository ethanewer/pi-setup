package org.apache.commons.lang3;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

/**
 * Hidden non-regression guards for the negated-argument containment fix:
 * interior excluded blocks still collapse to nothing, negated receivers keep
 * their exact definition, and mid-domain exclusions are still blanket-only.
 */
class CharRangeHiddenGuardsTest {

    @Test
    void testInteriorExclusionStillNeedsFullDomain() {
        // isNotIn(0x0100, 0x02FF) denotes [0, 0xFF] union [0x300, MAX]: no
        // proper interval contains it, only the full domain does.
        final CharRange interior = CharRange.isNotIn((char) 0x0100, (char) 0x02FF);
        assertTrue(CharRange.isIn((char) 0, Character.MAX_VALUE).contains(interior));
        assertFalse(CharRange.isIn((char) 0, (char) 0xFF).contains(interior));
        assertFalse(CharRange.isIn((char) 0x300, Character.MAX_VALUE).contains(interior));
        assertFalse(CharRange.isIn((char) 0x0100, (char) 0x02FF).contains(interior));
        assertFalse(CharRange.is('m').contains(interior));
    }

    @Test
    void testNegatedReceiverUntouched() {
        // negated receiver vs negated argument: definition unchanged
        assertTrue(CharRange.isNotIn('b', 'y').contains(CharRange.isNotIn('a', 'z')));
        assertFalse(CharRange.isNotIn('a', 'z').contains(CharRange.isNotIn('b', 'y')));
        assertTrue(CharRange.isNotIn('a', 'z').contains(CharRange.isNotIn('a', 'z')));
        // negated receiver vs plain range: definition unchanged
        assertTrue(CharRange.isNotIn('a', 'z').contains(CharRange.isIn('A', 'B')));
        assertFalse(CharRange.isNotIn('a', 'z').contains(CharRange.isIn('m', 'n')));
        // negated receiver vs character: definition unchanged
        assertTrue(CharRange.isNotIn('a', 'z').contains('A'));
        assertFalse(CharRange.isNotIn('a', 'z').contains('m'));
    }

    @Test
    void testNegatedArgumentMidDomainStillBlanket() {
        // fully interior excluded block, untouched by the fix
        final CharRange mid = CharRange.isNotIn((char) 0x1234, (char) 0x2345);
        assertTrue(CharRange.isIn((char) 0, Character.MAX_VALUE).contains(mid));
        assertFalse(CharRange.isIn((char) 0x1234, (char) 0x2345).contains(mid));
        assertFalse(CharRange.isNotIn((char) 0x1000, (char) 0x2000).contains(mid));
    }
}