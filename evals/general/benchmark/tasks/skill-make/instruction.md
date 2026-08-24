# Make

`/app/src/main.c` is a C source file. Write a `Makefile` in `/app/` that:

- Has a default target that compiles `src/main.c` into an executable named `hello` in `/app/`.
- Uses a dependency rule: the `hello` target must list `src/main.c` as a prerequisite (so `make` rebuilds it when the source changes).
- Compiles with `gcc` using standard flags (e.g. `gcc -O2 -o hello src/main.c`).

The source file `src/main.c` is:

```c
#include <stdio.h>
int main(void) {
    printf("BUILD_OK\n");
    return 0;
}
```

Then run `make` and run `./hello`.

When the build succeeds and you run `./hello`, the program prints:

```
BUILD_OK
```

Your Makefile will be evaluated by running `make` and then `./hello` — the produced executable must print exactly `BUILD_OK` on stdout. Verify in `/app/` with:

```bash
make
./hello
```

Leave both the Makefile and the built `hello` executable in `/app/`.