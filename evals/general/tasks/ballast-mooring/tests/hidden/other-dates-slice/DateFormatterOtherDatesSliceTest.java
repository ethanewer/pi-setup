/*
 * Authored hidden case for ballast-mooring (not upstream code).
 * Different expected VALUES from the upstream regression test: an epoch
 * date and a y2038 date, both with the year as the slice-final token and
 * more attributes following the slice end in the same CharSequence. Only a
 * real, input-general fix can pass these.
 */
package io.netty.handler.codec;

import org.junit.jupiter.api.Test;

import java.util.Date;

import static io.netty.handler.codec.DateFormatter.parseHttpDate;
import static org.junit.jupiter.api.Assertions.assertEquals;

public class DateFormatterOtherDatesSliceTest {

    @Test
    public void testEpochYearLast() {
        String header = "x=y; Expires=Thu 00:00:00 01 Jan 1970; Path=/";
        int start = header.indexOf("Thu 00");
        int end = header.indexOf("; Path=/");
        assertEquals(new Date(0L), parseHttpDate(header, start, end));
    }

    @Test
    public void testYear2038Last() {
        String header = "a=b; Expires=Sun 03:14:07 19 Jan 2038; Secure";
        int start = header.indexOf("Sun 03");
        int end = header.indexOf("; Secure");
        assertEquals(new Date(2147483647000L), parseHttpDate(header, start, end));
    }
}