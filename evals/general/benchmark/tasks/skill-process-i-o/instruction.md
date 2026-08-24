# Subprocess input/output

`/app/child.py` is a tiny helper program. It reads **one line from standard input** and prints that line **uppercased** to standard output. For example, if you run:

```
python3 /app/child.py
hello
```

it prints `HELLO`.

Write a Python program `/app/driver.py` that:

1. Uses Python's `subprocess` module to **launch `child.py` as a child process**.
2. Sends the string `hello world` (including a trailing newline) to the child's **standard input**.
3. **Captures the child's standard output**.
4. Writes the captured output (trimmed of any trailing whitespace/newlines) to the file `/app/result.txt`. The file should contain `HELLO WORLD` and nothing else.

Use `subprocess.Popen(..., stdin=subprocess.PIPE, stdout=subprocess.PIPE)` (or equivalent with `subprocess.run`), communicate with the child, then write the result file. Then run `/app/driver.py` so that `/app/result.txt` exists.

The verifier checks that `/app/result.txt` contains exactly `HELLO WORLD` (case-sensitive, trailing-newline tolerant).