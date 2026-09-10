package com.example.redoubtgate;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

import com.example.greeter.Greeter;
import com.example.liby.LibY;

class GreetingTest {

    @Test
    void greetingIsSurroundedByDoublePipes() {
        assertEquals("||Hello, Ada!||", new Greeter().greet("Ada"));
    }

    @Test
    void greetingForAnotherName() {
        assertEquals("||Hello, World!||", new Greeter().greet("World"));
    }

    @Test
    void libYStampIsPresent() {
        assertEquals("[lib-y]", LibY.stamp());
    }
}