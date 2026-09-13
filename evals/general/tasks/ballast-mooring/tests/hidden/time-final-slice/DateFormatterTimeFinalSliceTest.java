/*
 * Authored hidden case for ballast-mooring (not upstream code).
 * RFC-1123 token order but with the TIME value as the final token: the time
 * ends exactly at the slice end and another attribute follows.
 */
package io.netty.handler.codec;

import org.junit.jupiter.api.Test;

import java.util.Date;

import static io.netty.handler.codec.DateFormatter.parseHttpDate;
import static org.junit.jupiter.api.Assertions.assertEquals;

public class DateFormatterTimeFinalSliceTest {

    private static final Date DATE = new Date(784111777000L); // 06 Nov 1994 08:49:37 UTC

    @Test
    public void testTimeFinalDoubleDigit() {
        String header = "Set-Cookie: a=b; Expires=Sun, 06 Nov 1994 08:49:37; Path=/";
        int start = header.indexOf("Sun, 06");
        int end = header.indexOf("; Path=/");
        assertEquals(DATE, parseHttpDate(header, start, end));
    }

    @Test
    public void testTimeFinalSingleDigit() {
        String header = "a=b; Expires=Sunday, 06 Nov 1994 8:49:37; max-age=0";
        int start = header.indexOf("Sunday");
        int end = header.indexOf("; max-age");
        assertEquals(DATE, parseHttpDate(header, start, end));
    }
}