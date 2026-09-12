/*
 * Authored hidden case for cistern-compass (NOT an upstream test).
 *
 * Exercises the CSV reader path shared by @CsvSource and @CsvFileSource from
 * inputs the upstream regression test (trimsSpacesUsingStringTrim) does not
 * use. The contract under test: with the default
 * ignoreLeadingAndTrailingWhitespaces=true, trimming of unquoted columns must
 * apply ONLY to ASCII whitespace -- characters with Unicode code points less
 * than or equal to U+0020, exactly the semantics of String.trim(). Unicode
 * Whitespace characters ABOVE U+0020 must survive at the edges, and
 * non-whitespace control characters BELOW U+0020 must be trimmed.
 *
 * The discriminating tests here fail at the parent commit (where the reader
 * uses String.strip(), the Unicode-aware counterpart that inverts both
 * expectations) and pass with the correct ASCII-only trimming. Two guard
 * tests (trimming disabled, quoted columns) pin the surrounding contract and
 * pass in both states.
 */
package org.junit.jupiter.params.provider;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.params.provider.MockCsvAnnotationBuilder.csvSource;
import static org.mockito.Mockito.mock;

import java.util.stream.Stream;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtensionContext;

class CsvSourceWhitespaceSemanticsHiddenTests {

	@Test
	void preservesUnicodeWhitespaceAtBothEdges() {
		// U+1680 OGHAM SPACE MARK, U+2009 THIN SPACE, U+202F NARROW NO-BREAK
		// SPACE, U+205F MEDIUM MATHEMATICAL SPACE, U+3000 IDEOGRAPHIC SPACE,
		// U+00A0 NO-BREAK SPACE -- all White_Space above U+0020.
		var annotation = csvSource().lines(
			"\u1680ab\u2009,\u202Fcd\u205F",
			"\u3000ef\u3000,\u00A0gh\u00A0").build();

		var arguments = provideArguments(annotation);

		assertThat(arguments).containsExactly(
			new Object[][] { { "\u1680ab\u2009", "\u202Fcd\u205F" }, //
				{ "\u3000ef\u3000", "\u00A0gh\u00A0" } });
	}

	@Test
	void trimsNonWhitespaceControlsBelowU0020() {
		// U+0001, U+0002, U+000E and U+001B are control characters below
		// U+0020 that are NOT Unicode whitespace: trim() removes them from the
		// edges, strip() does not.
		var annotation = csvSource().lines(
			"\u0001aa,\u0002bb\u000E",
			"\u000Ecc\u0001,\u001Bdd").build();

		var arguments = provideArguments(annotation);

		assertThat(arguments).containsExactly(new Object[][] { { "aa", "bb" }, { "cc", "dd" } });
	}

	@Test
	void mixesAsciiAndUnicodeWhitespaceAroundContent() {
		var annotation = csvSource().lines("\t \u00A0x\u00A0 \t,\u0001\u00A0y\t").build();

		var arguments = provideArguments(annotation);

		// ASCII whitespace (\t, ' ') is trimmed; non-ASCII whitespace (NBSP)
		// at the edges survives; non-whitespace controls below U+0020 are
		// trimmed.
		assertThat(arguments).containsExactly(new Object[][] { { "\u00A0x\u00A0", "\u00A0y" } });
	}

	@Test
	void unicodeWhitespaceAndControlsAtBothEdges() {
		var annotation = csvSource().lines("\u0001\u3000a\u3000\u0001,\u2028b\u2029").build();

		var arguments = provideArguments(annotation);

		// U+3000 (Space_Separator) and U+2028/U+2029 (Line/Paragraph
		// Separator) survive trim(); the non-whitespace controls surrounding
		// them are removed from the edges.
		assertThat(arguments).containsExactly(new Object[][] { { "\u3000a\u3000", "\u2028b\u2029" } });
	}

	@Test
	void trimmingDisabledKeepsEveryEdgeCharacter() {
		var annotation = csvSource().lines("\u00A0a\u00A0,\u0001b\u0001")//
				.ignoreLeadingAndTrailingWhitespace(false).build();

		var arguments = provideArguments(annotation);

		assertThat(arguments).containsExactly(new Object[][] { { "\u00A0a\u00A0", "\u0001b\u0001" } });
	}

	@Test
	void quotedFieldsAreNeverTrimmed() {
		var annotation = csvSource().lines("'\u00A0q\u00A0'", "'\u0001q\u0001'").build();

		var arguments = provideArguments(annotation);

		assertThat(arguments).containsExactly(new Object[][] { { "\u00A0q\u00A0" }, //
			{ "\u0001q\u0001" } });
	}

	private Stream<Object[]> provideArguments(CsvSource annotation) {
		var provider = new CsvArgumentsProvider();
		provider.accept(annotation);
		return provider.provideArguments(mock(), mock(ExtensionContext.class)).map(Arguments::get);
	}
}