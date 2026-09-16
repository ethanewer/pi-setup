package com.example.redoubtgate;

import com.example.greeter.Greeter;
import com.example.liby.LibY;

/** Entry point of the redoubt-gate application. */
public final class Main {

    public static void main(String[] args) {
        String name = args.length == 0 ? "Cadet" : args[0];
        System.out.println(new Greeter().greet(name) + " " + LibY.stamp());
    }
}