In `/app` there is a C program `ub.c`. It currently reads the value of an uninitialized variable `b`, which is **undefined behavior** in C: the value of `b` is indeterminate, so the program may print any value and is non-deterministic across runs.

Fix `/app/ub.c` so that its behavior is well-defined (every variable is initialized before use) and it deterministically prints exactly:

```
total=6
```

Then build it (e.g. with `gcc -o /app/ub /app/ub.c`) and run it to confirm the output. Your edited `/app/ub.c` is what will be verified: it must compile and print `total=6` on every run.