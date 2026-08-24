# Syscalls

`/app/prog` is a small compiled C program that:

1. opens `/app/input.txt` (a 100-byte file),
2. performs **exactly one** `read` syscall to load the whole file into a buffer,
3. performs **exactly one** `write` syscall to send the buffer to stdout,
4. closes the file.

`strace` is installed. Your task is to observe the program's **system calls** with `strace` and count them.

Run the program under `strace`, tracing only `read` and `write` syscalls, saving the trace to a file:

```bash
strace -e trace=read,write -o /app/trace.txt /app/prog > /dev/null 2>&1
```

Then, counting the lines in `/app/trace.txt` that begin with `read(` and with `write(` respectively, write `/app/syscalls.txt` with exactly two lines:

```
reads=<count of read syscall lines>
writes=<count of write syscall lines>
```

For this program the trace should show a single `read(3, "...", 64) = 100` call and a single `write(1, "...", 100) = 100` call (the loader does its bookkeeping with other syscalls, not `read`/`write`), so the file should read:

```
reads=1
writes=1
```

The verifier reruns the same `strace` command itself, counts the same two kinds of lines in its own trace, and requires your two counts to match exactly.