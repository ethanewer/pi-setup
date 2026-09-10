package io.trino.sql.parser;

import io.trino.sql.SqlFormatter;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Hidden case 2: parse/format round-trips of interval literals through the
 * public {@link SqlParser} and {@link SqlFormatter} APIs, at both expression
 * and statement level, for unit forms the upstream suite does not round-trip.
 *
 * The formatter emits the interval qualifier from the parsed tree, so with
 * the seeded regression (YEAR/MONTH arms swapped in the AST builder) a YEAR
 * literal formats as MONTH and the round-trip assertions below break, even
 * though no upstream test round-trips these exact SQL strings.
 */
public class HiddenIntervalRoundTripCase
{
    private final SqlParser parser = new SqlParser();

    @Test
    public void expressionRoundTrips()
    {
        assertThat(SqlFormatter.formatSql(parser.createExpression("INTERVAL '2' YEAR")))
                .isEqualTo("INTERVAL '2' YEAR");

        assertThat(SqlFormatter.formatSql(parser.createExpression("INTERVAL '4' MONTH")))
                .isEqualTo("INTERVAL '4' MONTH");

        assertThat(SqlFormatter.formatSql(parser.createExpression("INTERVAL '1-6' YEAR TO MONTH")))
                .isEqualTo("INTERVAL '1-6' YEAR TO MONTH");

        assertThat(SqlFormatter.formatSql(parser.createExpression("INTERVAL -'3' HOUR")))
                .isEqualTo("INTERVAL -'3' HOUR");
    }

    @Test
    public void statementRoundTrips()
    {
        // Trino's formatter prints an explicit "AS alias" as a plain alias,
        // so the canonical form of these statements drops the AS.
        assertThat(SqlFormatter.formatSql(parser.createStatement("SELECT INTERVAL '6' MONTH AS span")).trim())
                .isEqualTo("SELECT INTERVAL '6' MONTH span");

        assertThat(SqlFormatter.formatSql(parser.createStatement("SELECT INTERVAL '30' DAY AS window")).trim())
                .isEqualTo("SELECT INTERVAL '30' DAY window");
    }
}