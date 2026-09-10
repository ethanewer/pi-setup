package com.example.formatter;

/**
 * Text formatting helpers, formatter 1.0.
 * The filled-text API: surround text with two copies of a fill character.
 */
public final class Formatter {

    private Formatter() {
    }

    /** Surrounds {@code text} with {@code fill}{@code fill} on both sides. */
    public static String format(String text, char fill) {
        if (text == null) {
            throw new NullPointerException("text");
        }
        return String.valueOf(fill) + fill + text + fill + fill;
    }
}