# C preprocessor tricks (token pasting, stringify)

Write a C program at `/app/tricks.c` that demonstrates C's **preprocessor** token-pasting and stringification operators.

The program must satisfy all of the following:

1. Define a macro `CAT(a, b)` that uses the token-pasting operator `##` to paste two tokens into one identifier.
2. Define a macro `Q(x)` that uses the stringification operator `#` to turn its argument into a string literal.
3. Declare a global integer variable `the_value = 1`.
4. `main()` must call `printf("%d %s\n", ...)` so that — using `CAT` to build the identifier `the_value`, and `Q(hello)` to build the string `"hello"` — the program prints exactly one line: `1 hello`.

A correct implementation looks like:

```c
#include <stdio.h>
#define CAT(a, b) a##b
#define Q(x) #x
int the_value = 1;
int main(void) {
    printf("%d %s\n", CAT(the, _value), Q(hello));
    return 0;
}
```

Compile it with `gcc` (installed in this environment) into `/tmp/tricks` and run it. Save the binary's stdout to `/app/out.txt` (a single line ending in a newline).

The verifier will: (a) confirm the source actually contains a `##` (token pasting is really exercised), (b) compile `/app/tricks.c` with `gcc`, (c) run the compiled binary, and (d) compare its printed output to `1 hello`.