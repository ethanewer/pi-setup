This container runs on an **x86_64** host, but your team ships binaries for ARM64
(AArch64) servers. In `/app/cross` there is a C program `hello.c`:

```c
#include <stdio.h>
int main(void) {
    printf("hello from arm64\n");
    return 0;
}
```

**Cross-compile** `hello.c` into a *statically linked* ARM64 (AArch64) ELF executable
using the installed cross toolchain `aarch64-linux-gnu-gcc` (GCC targeting AArch64):

```bash
aarch64-linux-gnu-gcc -static -O2 -o /app/cross/hello_arm /app/cross/hello.c
```

Then:

1. Verify the produced binary with `file /app/cross/hello_arm` — it must be identified as
   an ARM aarch64 executable (and, because of `-static`, reported as statically linked).
2. Write the target architecture name `aarch64` (lowercase, nothing else) into
   `/app/cross/target.txt`.

Notes:
- Do **not** compile with the host's native `gcc`/`cc` — that would produce an x86-64
  binary and fail verification.
- You may try to run `/app/cross/hello_arm`; on this x86-64 host it is expected to fail
  with an "exec format error" — that is fine and does not affect the grade. The verifier
  checks the ELF headers with `file`/`od`, not execution.