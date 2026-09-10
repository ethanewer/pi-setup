package com.example.redoubtgate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;

import org.junit.jupiter.api.Test;

import com.example.formatter.Formatter;
import com.example.greeter.Greeter;

/**
 * Hidden case H2: end-to-end proof that the runtime classpath really
 * carries formatter 1.0.0 (the release greeter 2.0.0 was built against)
 * and that the whole redoubt-gate application runs as shipped.
 */
class HiddenFormatterRestoredTest {

    @Test
    void asteriskFillStillWorks() {
        assertEquals("**ab**", Formatter.format("ab", '*'));
    }

    @Test
    void emptyNameStillGreets() {
        assertEquals("||Hello, !||", new Greeter().greet(""));
    }

    @Test
    void mainRunsEndToEnd() {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        PrintStream old = System.out;
        try {
            System.setOut(new PrintStream(out));
            Main.main(new String[] {"Zed"});
        } finally {
            System.setOut(old);
        }
        String text = out.toString();
        assertTrue(text.startsWith("||Hello, Zed!||"), "main output was: " + text);
    }
}