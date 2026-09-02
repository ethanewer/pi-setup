package com.lattice;

import java.io.BufferedReader;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;

/**
 * Read-only driver harness for the upload resolver.
 *
 * <p>Reads one client filename per line from the file named by the sole
 * command-line argument (UTF-8) and prints {@code resolve(line)} for each line.
 * This file must not be edited; the verifier builds it from the source tree.
 */
public final class Probe {

    public static void main(String[] args) throws IOException {
        if (args.length != 1) {
            throw new IllegalArgumentException("usage: Probe <input.txt>");
        }
        PrintWriter out = new PrintWriter(
                new OutputStreamWriter(System.out, StandardCharsets.UTF_8));
        try (BufferedReader in = new BufferedReader(new InputStreamReader(
                new FileInputStream(args[0]), StandardCharsets.UTF_8))) {
            String line;
            while ((line = in.readLine()) != null) {
                out.println(JaxUpload.resolve(line));
            }
        }
        out.flush();
    }
}
