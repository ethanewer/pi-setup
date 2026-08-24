# Legacy C / C++

`/app/legacy.c` is a small C program with a seeded bug: its `printf` format string does not match the types of its arguments, so running it produces **undefined / incorrect output**. A GNU C compiler (`gcc`) is installed.

Read the source, find the format/argument mismatch, and **fix the `printf` line so the program compiles (and is well-defined) and prints exactly this line** when run:

```
c=A i=10
```

Do not change the values of the variables, only the format string. Edit `/app/legacy.c` accordingly.

Then compile and run it:

```bash
gcc /app/legacy.c -o /app/legacy
/app/legacy
```

Capture the program's printed line (the first line of output) and write it verbatim to `/app/run_output.txt`, ending with a newline.

For example, if the correct `printf` were `printf("c=%c i=%d\n", c, i);`, the output line would be `c=A i=10`.

Afterward `/app/run_output.txt` must exist and contain exactly `c=A i=10` (with trailing newline). The grader recompiles your `/app/legacy.c` and checks both that it produces that line and that you recorded it.