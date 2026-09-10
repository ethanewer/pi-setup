package com.example.greeter;

import com.example.conventions.Conventions;
import com.example.formatter.Formatter;

/**
 * Greeting service.  Built against formatter 1.0.0's filled-text API via
 * the conventions artifact (which pins formatter 1.0.0).
 */
public final class Greeter {

    /** Renders a greeting like {@code ||Hello, NAME!||}. */
    public String greet(String name) {
        return Formatter.format("Hello, " + name + "!", Conventions.SURROUND);
    }
}