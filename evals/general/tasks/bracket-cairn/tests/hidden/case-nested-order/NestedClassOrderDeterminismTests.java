/*
 * Authored hidden case for the bracket-cairn task: nested-class ordering.
 * Exercises org.junit.platform.commons.util.ReflectionUtils entry points from
 * inputs the upstream regression test never uses (different class names,
 * predicate filtering, an inheritance chain, an interface declaring nested
 * classes). Expected orders were computed from the ordering contract: each
 * nested class's fully qualified Class#getName(), compared first by
 * String#hashCode() and then by String#compareTo.
 */
package org.junit.platform.commons.util;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;

import org.junit.jupiter.api.Test;

class NestedClassOrderDeterminismTests {

	@Test
	void nestedClassesOfSameEnclosingClassFollowDeterministicOrder() {
		// Prefix: org.junit.platform.commons.util.NestedClassOrderDeterminismTests$KitchenSink$
		List<String> names = ReflectionUtils.findNestedClasses(KitchenSink.class, c -> true).stream()
				.map(Class::getSimpleName).toList();

		assertThat(names).containsExactly("Kiwi", "Plum", "Cherry", "Apple", "Grape", "Lemon", "Mango", "Peach");
	}

	@Test
	void predicateFilteringKeepsTheDeterministicRelativeOrder() {
		// Simple names longer than 4 characters, in the same relative order.
		List<String> names = ReflectionUtils.findNestedClasses(KitchenSink.class, c -> c.getSimpleName().length() > 4)
				.stream().map(Class::getSimpleName).toList();

		assertThat(names).containsExactly("Cherry", "Apple", "Grape", "Lemon", "Mango", "Peach");
	}

	@Test
	void inheritedNestedClassesStayGroupedByDeclaringType() {
		// The derived class's own nested classes first (deterministic within the
		// group), then the superclass's nested classes (deterministic within that
		// group).
		List<String> names = ReflectionUtils.findNestedClasses(LayerDerived.class, c -> true).stream()
				.map(Class::getSimpleName).toList();

		assertThat(names).containsExactly("Dams", "Durian", "Dragonfruit", "Litchi", "Loquat", "Lucuma", "Lychee");
	}

	@Test
	void interfaceNestedClassesComeAfterTheImplementingClasssOwn() {
		List<String> names = ReflectionUtils.findNestedClasses(Router.class, c -> true).stream()
				.map(Class::getSimpleName).toList();

		assertThat(names).containsExactly("Rack", "Rout", "Wane", "Wick", "Wilt");
	}

	@Test
	void streamNestedClassesMatchesFindNestedClasses() {
		List<String> names = ReflectionUtils.streamNestedClasses(KitchenSink.class, c -> true).map(Class::getSimpleName)
				.toList();

		assertThat(names).containsExactly("Kiwi", "Plum", "Cherry", "Apple", "Grape", "Lemon", "Mango", "Peach");
	}

	static class KitchenSink {
		static class Apple {
		}

		static class Mango {
		}

		static class Kiwi {
		}

		static class Cherry {
		}

		static class Plum {
		}

		static class Grape {
		}

		static class Lemon {
		}

		static class Peach {
		}
	}

	static class LayerBase {
		static class Litchi {
		}

		static class Loquat {
		}

		static class Lucuma {
		}

		static class Lychee {
		}
	}

	static class LayerDerived extends LayerBase {
		static class Dams {
		}

		static class Durian {
		}

		static class Dragonfruit {
		}
	}

	interface Gateway {
		static class Wane {
		}

		static class Wick {
		}

		static class Wilt {
		}
	}

	static class Router implements Gateway {
		static class Rack {
		}

		static class Rout {
		}
	}

}