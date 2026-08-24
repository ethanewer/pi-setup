# Capture child output through a pseudo-terminal (pty)

`/app/printer.py` prints three lines then exits:

```
line one
line two
line three
```

Write a Python program `/app/pty_runner.py` that runs `printer.py` as a child process connected to a **pseudo-terminal**, using Python's built-in `pty` module:

- Create the master/slave pair with `pty.openpty()`.
- Spawn the child so that its **standard output (and optionally standard error)** are the **slave** fd of the pty (e.g. with `subprocess.Popen([...], stdout=slave_fd, stderr=slave_fd, ...)`, passing `stdin=subprocess.PIPE`).
- Read from the **master** fd (in a loop) until the child exits / the pty closes, accumulating the raw bytes.
- Close the master fd.

Then write the **raw captured bytes** (the accumulated output) to the file `/app/pty_out.txt` (open it in binary mode `'wb'`). Do **not** alter the bytes.

Run `/app/pty_runner.py` so `/app/pty_out.txt` exists. Note that because the output goes through a real terminal, `\n` in the child's output is normally emitted to the master as `\r\n`. That is expected and fine — write the bytes exactly as read.

The verifier reads `/app/pty_out.txt`, normalizes `\r\n` sequences to `\n`, and requires the result to equal `line one\nline two\nline three\n`.