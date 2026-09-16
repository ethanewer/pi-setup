/*
 * Authored hidden case for ballast-mooring (not upstream code).
 * The Expires date sits mid-header with a non-zero slice start, and the
 * token that completes the parse ends exactly at the slice end while more
 * attributes follow in the same CharSequence.
 */
package io.netty.handler.codec;

import org.junit.jupiter.api.Test;

import java.util.Date;

import static io.netty.handler.codec.DateFormatter.parseHttpDate;
import static org.junit.jupiter.api.Assertions.assertEquals;

public class DateFormatterMidHeaderSliceTest {

    private static final Date DATE = new Date(784111777000L); // 06 Nov 1994 08:49:37 UTC

    @Test
    public void testAsctimeDateFollowedByTwoAttributes() {
        String header = "foo=bar; Path=/; Expires=Sun 08:49:37 06 Nov 1994; Secure; HttpOnly";
        int start = header.indexOf("Sun 08");
        int end = header.indexOf("; Secure");
        assertEquals(DATE, parseHttpDate(header, start, end));
    }

    @Test
    public void testAsctimeDateThenSpaceSeparatedAttribute() {
        String header = "foo=bar; Expires=Sun 08:49:37 06 Nov 1994 Max-Age=0";
        int start = header.indexOf("Sun 08");
        int end = start + "Sun 08:49:37 06 Nov 1994".length();
        assertEquals(DATE, parseHttpDate(header, start, end));
    }
}