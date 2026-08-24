There is a C program at `/app/vuln.c`, already compiled to `/app/vuln`. It reads a line of
input from stdin into a fixed-size buffer and carries an `authenticated` flag inside the
same struct. Inspect the source. The program contains a classic **buffer overflow**
vulnerability: the input-copying loop can write past the end of the 16-byte `token` field
and overwrite the adjacent `authenticated` field in memory.

Your goal — do all three:

1. **Craft an exploit input.** Create a file `/app/payload` containing a single line of
   plain text such that, when fed as stdin to the vulnerable binary
   (`/app/vuln < /app/payload`), the overflow makes the program print `ACCESS GRANTED`.
2. **Explain the vulnerability.** Write a short explanation to `/app/explanation.txt`
   describing (in your own words) the buffer overflow and how your input exploits it.
3. **Write a fixed version.** Create `/app/safe.c` — a corrected program (same behavior
   otherwise) that no longer lets input overflow the `token` field. It must compile
   (e.g. `gcc -O0 -o /app/safe /app/safe.c`) and, when run with the *same* `/app/payload`
   as stdin, must **not** print `ACCESS GRANTED`.

Note: the copy loop in `vuln.c` stops at a newline or end-of-string, so a payload that
overflows by a few bytes past position 16 is enough. Your `/app/payload`,
`/app/explanation.txt`, and `/app/safe.c` are what get verified.
