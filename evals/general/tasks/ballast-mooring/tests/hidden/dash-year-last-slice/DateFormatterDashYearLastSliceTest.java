/*
 * Authored hidden case for ballast-mooring (not upstream code).
 * Dash-separated RFC-850 style date with a two-digit year whose token is the
 * LAST token of the slice, immediately followed by another attribute.
 */
package io.netty.handler.codec;

import org.junit.jupiter.api.Test;

import java.util.Date;

import static io.netty.handler.codec.DateFormatter.parseHttpDate;
import static org.junit.jupiter.api.Assertions.assertEquals;

public class DateFormatterDashYearLastSliceTest {

    private static final Date DATE = new Date(784111777000L); // 06 Nov 1994 08:49:37 UTC

    @Test
    public void testDashSeparatorTwoDigitYearLast() {
        String header = "x=1; Expires=Sun, 06-Nov-94 08:49:37; Secure";
        int start = header.indexOf("Sun, 06");
        int end = header.indexOf("; Secure");
        assertEquals(DATE, parseHttpDate(header, start, end));
    }

    @Test
    public void testDashSeparatorSingleDigitDayYearLast() {
        String header = "cookie=2; Expires=Sun, 6-Nov-94 08:49:37; SameSite=Lax";
        int start = header.indexOf("Sun, 6-");
        int end = header.indexOf("; SameSite");
        assertEquals(DATE, parseHttpDate(header, start, end));
    }
}