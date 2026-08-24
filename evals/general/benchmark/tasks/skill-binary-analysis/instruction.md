`/app/passcheck` is a compiled native executable that acts as a password gate. It reads a single command-line argument and prints `ALLOWED` only if that argument is the accepted secret value, otherwise it prints `DENIED`.

Your task is to perform binary/file analysis to find the accepted secret value:
- Inspect `/app/passcheck` as raw bytes / strings. The program stores its expected secret as a literal string constant inside the binary image.
- Recover that exact secret string.
- Write the secret (no quotes, no trailing whitespace) to `/app/found.txt`.

You may run, disassemble bytes, search the file for embedded text, or reason about its structure. The reward checks that `/app/found.txt` contains the exact accepted secret.
