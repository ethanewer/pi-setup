package com.example.redoubtgate;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

import com.example.formatter.Formatter;
import com.example.greeter.Greeter;

/**
 * Hidden case H1: the previously-missing functionality.  formatter 2.0.0
 * dropped the filled-text API {@code format(String, char)}; these tests
 * compile and pass only when formatter 1.0.0 actually wins the dependency
 * graph at runtime (under 2.0.0 they die with NoSuchMethodError).
 */
class HiddenGreetingTest {

    @Test
    void fillEscapesText() {
        assertEquals("##x##", Formatter.format("x", '#'));
    }

    @Test
    void greetUsesFilledFormat() {
        assertEquals("||Hello, Grace!||", new Greeter().greet("Grace"));
    }

    @Test
    void greetHandlesWideCharacters() {
        assertEquals("||Hello, 世界!||", new Greeter().greet("世界"));
    }
}