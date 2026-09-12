/*
 * Authored hidden case for cistern-compass (NOT an upstream test).
 *
 * Exercises the shared CSV reader through the @CsvFileSource code path
 * (CsvFileArgumentsProvider -> CsvReaderFactory) with a file payload the
 * upstream regression test (trimsSpacesUsingStringTrim) does not use: rows of
 * unquoted columns whose edges hold Unicode White_Space above U+0020 (U+00A0
 * NBSP, U+3000 ideographic space) and non-whitespace control characters below
 * U+0020 (U+0001), asserting the ASCII-only trim() contract for file-loaded
 * arguments as well. Fails at the parent commit, passes with the fix.
 *
 * The file is fed through the provider's InputStreamProvider hook exactly the
 * way the project's own CsvFileArgumentsProviderTests does, so no classpath
 * resource is needed.
 */
package org.junit.jupiter.params.provider;

import static java.nio.charset.StandardCharsets.UTF_8;
import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.params.provider.MockCsvAnnotationBuilder.csvFileSource;
import static org.mockito.Mockito.doCallRealMethod;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.Optional;
import java.util.stream.Stream;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.junit.jupiter.params.provider.CsvFileArgumentsProvider.InputStreamProvider;

class CsvFileSourceWhitespaceSemanticsHiddenTests {

	@Test
	void trimsFileColumnsWithAsciiOnlySemantics() {
		var annotation = csvFileSource().resources("hidden-trim.csv").build();

		var content = "aa, \u00A0bb \ncc\u0001, \u3000dd\n";

		var arguments = provideArguments(annotation, content);

		// trim(): leading/trailing NBSP and ideographic space survive, the
		// trailing U+0001 is trimmed. strip() at the parent inverts all three.
		assertThat(arguments).containsExactly(//
			array("aa", "\u00A0bb"), //
			array("cc", "\u3000dd")//
		);
	}

	@Test
	void preservesQuotedFileColumnsAndDisabledTrimming() {
		var annotation = csvFileSource().resources("hidden-trim.csv")
				.ignoreLeadingAndTrailingWhitespace(false).build();

		var content = "\" \u00A0q \u00A0\", \u0001raw\t\n";

		var arguments = provideArguments(annotation, content);

		// With trimming disabled nothing is stripped; the quoted column (default
		// double-quote character for @CsvFileSource) keeps its inner characters
		// verbatim.
		assertThat(arguments).containsExactly(array(" \u00A0q \u00A0", " \u0001raw\t"));
	}

	private Stream<Object[]> provideArguments(CsvFileSource annotation, String content) {
		return provideArguments(new ByteArrayInputStream(content.getBytes(UTF_8)), annotation);
	}

	private Stream<Object[]> provideArguments(InputStream inputStream, CsvFileSource annotation) {
		var provider = new CsvFileArgumentsProvider(new InputStreamProvider() {
			@Override
			public InputStream openClasspathResource(Class<?> baseClass, String path) {
				assertThat(path).isEqualTo(annotation.resources()[0]);
				return inputStream;
			}

			@Override
			public InputStream openFile(String path) {
				assertThat(path).isEqualTo(annotation.files()[0]);
				return inputStream;
			}
		});
		provider.accept(annotation);
		var context = mock(ExtensionContext.class);
		when(context.getTestClass()).thenReturn(Optional.of(CsvFileSourceWhitespaceSemanticsHiddenTests.class));
		doCallRealMethod().when(context).getRequiredTestClass();
		return provider.provideArguments(mock(), context).map(Arguments::get);
	}

	private static String[] array(String... elements) {
		return elements;
	}
}