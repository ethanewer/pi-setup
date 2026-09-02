You are analyzing a compiled binary with **objdump** (and, optionally, gdb) to recover a hidden secret string.

In `/app` there is a compiled binary `/app/mystery` built from C source. When run normally it prints only a numeric hash — **not** the secret. The secret constant string is baked into the binary's `.rodata`/text section.

Your goal: discover the secret string embedded in the binary.

Use `objdump` (e.g. `objdump -s /app/mystery`, or `-d`/`-s -d` to inspect) to locate it. (If you prefer, `gdb` can also be used to dump memory.

Write the secret to `/app/secret.txt` as a plain text string (no quotes, no trailing newline required).

Run your analysis so `/app/secret.txt` contains the correct secret string. `objdump`, `gcc`, and `gdb` are installed.