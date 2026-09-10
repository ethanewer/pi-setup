package io.trino.sql.parser;

import io.trino.sql.tree.CompositeIntervalQualifier;
import io.trino.sql.tree.IntervalDataType;
import io.trino.sql.tree.IntervalField;
import io.trino.sql.tree.NodeLocation;
import io.trino.sql.tree.SimpleIntervalQualifier;
import org.junit.jupiter.api.Test;

import java.util.OptionalInt;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Hidden case 1: interval TYPE variants that the upstream suite does not
 * assert -- bare (parenthesis-free) simple year/month/day/hour/minute units
 * and precision values other than 1 -- all through the public
 * {@link SqlParser#createType(String)} API.
 *
 * With the seeded regression present (YEAR/MONTH arms of the simple
 * year-month switch swapped in the AST builder) the year- and month-bearing
 * assertions below fail, even though no upstream test asserts them.
 */
public class HiddenIntervalTypesCase
{
    private final SqlParser parser = new SqlParser();

    @Test
    public void bareYearMonthDayHourMinuteUnits()
    {
        assertThat(parser.createType("INTERVAL YEAR"))
                .isEqualTo(new IntervalDataType(new NodeLocation(1, 1), new SimpleIntervalQualifier(new NodeLocation(1, 10), OptionalInt.empty(), new IntervalField.Year())));

        assertThat(parser.createType("INTERVAL MONTH"))
                .isEqualTo(new IntervalDataType(new NodeLocation(1, 1), new SimpleIntervalQualifier(new NodeLocation(1, 10), OptionalInt.empty(), new IntervalField.Month())));

        assertThat(parser.createType("INTERVAL DAY"))
                .isEqualTo(new IntervalDataType(new NodeLocation(1, 1), new SimpleIntervalQualifier(new NodeLocation(1, 10), OptionalInt.empty(), new IntervalField.Day())));

        assertThat(parser.createType("INTERVAL HOUR"))
                .isEqualTo(new IntervalDataType(new NodeLocation(1, 1), new SimpleIntervalQualifier(new NodeLocation(1, 10), OptionalInt.empty(), new IntervalField.Hour())));

        assertThat(parser.createType("INTERVAL MINUTE"))
                .isEqualTo(new IntervalDataType(new NodeLocation(1, 1), new SimpleIntervalQualifier(new NodeLocation(1, 10), OptionalInt.empty(), new IntervalField.Minute())));
    }

    @Test
    public void nonTrivialPrecisionVariants()
    {
        assertThat(parser.createType("INTERVAL YEAR(3) TO MONTH"))
                .isEqualTo(new IntervalDataType(new NodeLocation(1, 1), new CompositeIntervalQualifier(new NodeLocation(1, 10), OptionalInt.of(3), new IntervalField.Year(), new IntervalField.Month())));

        assertThat(parser.createType("INTERVAL DAY(9) TO SECOND(4)"))
                .isEqualTo(new IntervalDataType(new NodeLocation(1, 1), new CompositeIntervalQualifier(new NodeLocation(1, 10), OptionalInt.of(9), new IntervalField.Day(), new IntervalField.Second(OptionalInt.of(4)))));

        assertThat(parser.createType("INTERVAL SECOND(5, 7)"))
                .isEqualTo(new IntervalDataType(new NodeLocation(1, 1), new SimpleIntervalQualifier(new NodeLocation(1, 10), OptionalInt.of(5), new IntervalField.Second(OptionalInt.of(7)))));

        assertThat(parser.createType("INTERVAL HOUR(2) TO MINUTE"))
                .isEqualTo(new IntervalDataType(new NodeLocation(1, 1), new CompositeIntervalQualifier(new NodeLocation(1, 10), OptionalInt.of(2), new IntervalField.Hour(), new IntervalField.Minute())));
    }
}