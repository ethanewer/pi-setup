/*
 * Authored hidden case for the bracket-cairn task: nested-class ordering.
 * Exercises the public org.junit.platform.commons.support.ReflectionSupport
 * facade (which delegates to ReflectionUtils) through the stream API and a
 * different arrangement of nested classes, including an interface declaring
 * nested classes inherited by an implementing class.
 */
package org.junit.platform.commons.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;

import org.junit.jupiter.api.Test;

class NestedClassStreamOrderTests {

	@Test
	void supportFacadeStreamsNestedClassesInDeterministicOrder() {
		// Prefix: org.junit.platform.commons.support.NestedClassStreamOrderTests$FruitBasket$
		List<String> names = ReflectionSupport.streamNestedClasses(FruitBasket.class, c -> true)
				.map(Class::getSimpleName).toList();

		assertThat(names).containsExactly("Fig", "Foxtail", "Feijoa", "Fennel");
	}

	@Test
	void supportFacadeKeepsInterfaceGroupingWhenInherited() {
		// Hub's own nested classes first, then Signal's, each group in the
		// deterministic order.
		List<String> names = ReflectionSupport.findNestedClasses(Hub.class, c -> true).stream()
				.map(Class::getSimpleName).toList();

		assertThat(names).containsExactly("Hail", "Hoot", "Hum", "Sway", "Squall", "Swell");
	}

	static class FruitBasket {
		static class Fig {
		}

		static class Fennel {
		}

		static class Feijoa {
		}

		static class Foxtail {
		}
	}

	interface Signal {
		static class Sway {
		}

		static class Squall {
		}

		static class Swell {
		}
	}

	static class Hub implements Signal {
		static class Hum {
		}

		static class Hail {
		}

		static class Hoot {
		}
	}

}