package com.example.formatter;

/**
 * Text formatting helpers, formatter 2.0.
 * Modernized: the char-fill overload was dropped in favour of a single
 * fixed decorative form.
 */
public final class Formatter {

    private Formatter() {
    }

    /** Wraps {@code text} in square brackets. */
    public static String format(String text) {
        if (text == null) {
            throw new NullPointerException("text");
        }
        return "[" + text + "]";
    }
}