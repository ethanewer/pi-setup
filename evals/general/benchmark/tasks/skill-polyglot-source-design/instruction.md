# Polyglot source file

Create a single source file `/app/polyglot` that is **simultaneously a valid script in both Bash and Python 3** — a polyglot — such that running it with **either** interpreter prints exactly the line `42`.

Requirements that the verifier checks:

1. Running `python3 /app/polyglot` exits 0 and prints `42`.
2. Running `bash /app/polyglot` exits 0 and prints `42`.
3. The file is one and the same source file (no separate program files, no runtime-generated helper).

A classic, minimal technique: start the file with a `#!/bin/bash` shebang, then a line made of a double-quoted shell statement that is simultaneously a harmless Python string expression — for example `"exec" "python3" "$0"` (a concurrent adjacent string-literal expression in Python, and in Bash the `exec` shell builtin that hands the current script off to Python). The rest of the file is Python. This keeps the file identical for both interpreters.

You may use any valid polyglot construction you like as long as both checks above pass.