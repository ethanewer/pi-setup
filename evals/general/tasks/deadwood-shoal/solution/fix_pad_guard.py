#!/usr/bin/env python3
"""Apply the upstream LANG-1828 guard to StringUtils.java.

The four public pad overloads (leftPad/rightPad x char/String pad) begin with
`if (str == null) { return null; }` and then compute `pads = size -
str.length()`.  A requested size inside the overflow band makes that
subtraction wrap to a huge positive count and the code allocates a
multi-gigabyte array, killing the JVM.  The fix short-circuits any size that
is not greater than the string's length:

    if (str == null || size <= str.length()) {
        return str;
    }

This script rewrites exactly the four method guards in place; it raises if
the input does not have the expected shape, so the oracle fails loudly on any
tree that diverges from the pinned parent.
"""
import sys

SIGNATURES = {
    "public static String leftPad(final String str, final int size, final char padChar) {",
    "public static String leftPad(final String str, final int size, String padStr) {",
    "public static String rightPad(final String str, final int size, final char padChar) {",
    "public static String rightPad(final String str, final int size, String padStr) {",
}


def main(path: str) -> None:
    with open(path, "r", encoding="utf-8") as fh:
        lines = fh.readlines()

    out = []
    i = 0
    n = len(lines)
    replaced = 0
    while i < n:
        line = lines[i]
        stripped = line.strip()
        if stripped in SIGNATURES:
            out.append(line)
            i += 1
            if i >= n or lines[i].strip() != "if (str == null) {":
                raise SystemExit(
                    "expected null-guard after %r at line %d" % (stripped, i))
            if i + 2 >= n \
                    or lines[i + 1].strip() != "return null;" \
                    or lines[i + 2].strip() != "}":
                raise SystemExit(
                    "unexpected guard shape after %r at line %d" % (stripped, i))
            out.append("        if (str == null || size <= str.length()) {\n")
            out.append("            return str;\n")
            out.append("        }\n")
            i += 3
            replaced += 1
            continue
        out.append(line)
        i += 1

    if replaced != 4:
        raise SystemExit("expected 4 pad overloads to be guarded, guarded %d" % replaced)

    with open(path, "w", encoding="utf-8") as fh:
        fh.writelines(out)
    print("guarded %d pad overloads in %s" % (replaced, path))


if __name__ == "__main__":
    main(sys.argv[1])